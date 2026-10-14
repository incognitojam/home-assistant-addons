import { test, expect } from '../lib/fixtures.mjs';
import { openTerminal, screenText, waitForText } from '../lib/terminal.mjs';

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
    await waitForText(page, screen, { message: 'Claude repainted after the reload' });
    expect(await screenText(page), 'Claude on screen, not only in the scrollback').toMatch(screen);
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
