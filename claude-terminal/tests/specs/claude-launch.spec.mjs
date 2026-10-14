import { test, expect } from '../lib/fixtures.mjs';
import { cellCenter, openTerminal, screenText, waitForText } from '../lib/terminal.mjs';

// These check that the Claude binary in the image starts (catching e.g. a
// musl/glibc mismatch), not Claude's UI, so the patterns are deliberately
// loose: any one recognisable phrase is enough.

test.use({ addonEnv: { AUTO_LAUNCH_CLAUDE: 'true', AUTO_UPDATE_CLAUDE: 'false' } });

// Claude draws its welcome banner before checking connectivity, so this works
// without network access.
test('auto-launched Claude starts and renders its UI', async ({ page, terminalUrl }) => {
    await openTerminal(page, terminalUrl);
    await waitForText(page, /welcome to claude|unable to connect to anthropic|text style|login method/i, {
        timeout: 30_000,
        message: 'Claude to render its welcome banner or first-run screen',
    });
});

// The reloaded page must show Claude again without a keypress (Claude only
// repaints when its size changes, so this relies on tmux redrawing it) and it
// must be the same Claude process.
test('page reload reattaches to the running Claude and repaints it', async ({ page, terminalUrl, addon }) => {
    const claudePids = async () => (await addon.exec('pgrep', '-f', '^claude( |$)')).trim();
    const screen = /welcome to claude|unable to connect to anthropic|text style|login method/i;

    await openTerminal(page, terminalUrl);
    await waitForText(page, screen, { timeout: 30_000, message: 'Claude to render before the reload' });
    const before = await claudePids();
    expect(before, 'a running Claude process').not.toBe('');

    await page.reload();
    await page.waitForFunction(() => window.term?.buffer?.active !== undefined);
    // Wait on the screen, not the whole buffer: the history replayed on
    // reattach can match in the scrollback before tmux has redrawn the screen.
    await expect.poll(() => screenText(page), {
        message: 'Claude repainted on screen after the reload, not only in the scrollback',
    }).toMatch(screen);
    expect(await claudePids(), 'the same Claude process after the reload').toBe(before);
});

// With no credentials, Claude then checks it can reach api.anthropic.com and
// shows onboarding (theme picker, then login). Needs network; CI runs @network
// tests as a separate step, and `npm test -- --grep-invert @network` skips it.
test('auto-launched Claude reaches its first-run onboarding', { tag: '@network' }, async ({ page, terminalUrl }) => {
    await openTerminal(page, terminalUrl);
    await waitForText(page, /text style|dark mode|light mode|login method|log ?in to|sign ?in/i, {
        timeout: 45_000,
        message: 'Claude onboarding (theme picker or login) in the terminal',
    });
});

// Signing in means opening Claude's long OAuth URL, which wraps over several
// rows, and pasting back a code. Claude marks every row with an OSC 8 link to
// the whole URL, and tmux must pass it through so that clicking any row opens
// the complete URL. Stops at the paste prompt with a made-up code.
test('the login URL opens in full from every wrapped row and a pasted code reaches Claude', { tag: '@network' }, async ({ page, terminalUrl }) => {
    // Record what xterm.js would open instead of opening it.
    await page.addInitScript(() => {
        window.e2eOpened = [];
        window.open = () => ({ opener: null, location: { set href(url) { window.e2eOpened.push(url); } } });
    });
    const prompts = [];
    page.on('dialog', dialog => {
        prompts.push(dialog.message());
        dialog.accept();
    });

    await openTerminal(page, terminalUrl);
    const [first] = await waitForText(page, /text style|select login method/i, {
        timeout: 45_000,
        message: 'Claude onboarding (theme picker or login method)',
    });
    if (/text style/i.test(first)) await pressKey(page, 'Enter');
    await waitForText(page, /select login method/i, { message: 'the login method choice' });

    // Move the highlight to the subscription option by its label.
    const [, highlighted] = await waitForText(page, /❯\s*(\d+)\./);
    const [, wanted] = await waitForText(page, /(\d+)\.\s*Claude account with subscription/);
    for (let i = Number(highlighted); i < Number(wanted); i++) await pressKey(page, 'ArrowDown');
    await pressKey(page, 'Enter');
    await waitForText(page, /paste code here/i, { timeout: 30_000, message: 'the login URL and paste prompt' });

    const rows = await page.evaluate(() => {
        const buffer = window.term.buffer.active;
        const rows = [];
        for (let row = 0; row < window.term.rows; row++) {
            const text = buffer.getLine(buffer.viewportY + row).translateToString(true).trim();
            if (rows.length ? text : text.startsWith('https://')) rows.push({ row, text });
            else if (rows.length) break;
        }
        return rows;
    });
    const url = rows.map(({ text }) => text).join('');
    expect(rows.length, 'the login URL wraps over several rows').toBeGreaterThan(1);
    const parsed = new URL(url);
    expect(parsed.pathname).toMatch(/\/oauth\/authorize$/);
    for (const param of ['client_id', 'redirect_uri', 'code_challenge', 'state']) {
        expect(parsed.searchParams.get(param), `login URL parameter ${param}`).toBeTruthy();
    }

    expect(await page.evaluate(() => window.term.modes.mouseTrackingMode), 'mouse left to the browser for selecting').toBe('none');
    for (const { row } of rows) {
        const { x, y } = await cellCenter(page, { row, col: 5 });
        await page.mouse.move(x, y);
        // xterm.js shows a pointer cursor over a link.
        await expect(page.locator('.xterm-cursor-pointer'), `row ${row} of the login URL to be a link`).toHaveCount(1);
        await page.mouse.click(x, y);
        await expect.poll(() => page.evaluate(() => window.e2eOpened.splice(0)), {
            message: `clicking row ${row} of the login URL to open it`,
        }).toEqual([url]);
    }
    expect(prompts, 'xterm.js asks before opening each OSC 8 link').toHaveLength(rows.length);
    expect(prompts.every(prompt => prompt.includes(url)), 'every prompt names the full URL').toBe(true);

    // Claude may mask the code, so compare its length, not its text.
    const code = 'e2e-synthetic-code-0123456789';
    await page.evaluate(code => window.term.paste(code), code);
    const [, entered] = await waitForText(page, /paste code here if prompted > (\S+)/i, { message: 'the pasted code in the prompt' });
    expect(entered).toHaveLength(code.length);
});

async function pressKey(page, key) {
    await page.evaluate(() => window.term.focus());
    await page.keyboard.press(key);
}
