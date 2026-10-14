import { test, expect, openBashShell } from '../lib/fixtures.mjs';
import { cellCenter, locateText, openTerminal, typeLine, waitForText } from '../lib/terminal.mjs';

// The session runs inside tmux, which re-renders it for the browser. These
// check that what Claude relies on still reaches xterm.js, and that tmux does
// not take over the mouse or the scrollback.

test.beforeEach(async ({ page, terminalUrl }) => {
    await openTerminal(page, terminalUrl);
    await openBashShell(page);
});

// Claude prints its login URL as an OSC 8 hyperlink on every wrapped row, so
// clicking any row opens the whole URL. The link text here is not a URL, so
// only the OSC 8 target can explain the URL xterm.js opens.
test('OSC 8 hyperlinks reach xterm.js on every wrapped row', async ({ page }) => {
    const url = 'https://example.com/e2e/osc8-target/end';
    await typeLine(page, `printf '\\e]8;;${url}\\e\\\\%s\\e]8;;\\e\\\\\\n' "osc8-text-$(printf 'x%.0s' $(seq 300))"`);
    await waitForText(page, /^osc8-text-x+$/m);

    const start = await locateText(page, 'osc8-text-');
    const secondRow = await cellCenter(page, { row: start.row + 1, col: 5 });
    const prompts = [];
    page.on('dialog', dialog => {
        prompts.push(dialog.message());
        dialog.dismiss();
    });
    await page.mouse.move(secondRow.x, secondRow.y);
    await page.mouse.click(secondRow.x, secondRow.y);
    await expect.poll(() => prompts, { message: 'xterm.js to prompt before opening the link' }).toHaveLength(1);
    expect(prompts[0]).toContain(url);
});

test('24-bit colour reaches xterm.js unchanged', async ({ page }) => {
    await typeLine(page, `printf '\\e[38;2;1;2;3mrgb-marker\\e[0m\\n'`);
    await waitForText(page, /^rgb-marker$/m);
    const { row, col } = await locateText(page, 'rgb-marker');
    const colour = await page.evaluate(({ row, col }) => {
        const buffer = window.term.buffer.active;
        const cell = buffer.getLine(buffer.viewportY + row).getCell(col);
        return { rgb: cell.isFgRGB(), value: cell.getFgColor() };
    }, { row, col });
    expect(colour).toEqual({ rgb: true, value: 0x010203 });
});

test('the window title reaches the browser tab', async ({ page }) => {
    await typeLine(page, `printf '\\e]2;e2e-title\\a'`);
    await expect(page).toHaveTitle(/^e2e-title \|/);
});

// Compares the bytes xterm.js sends for each key with the bytes a raw-mode
// reader receives, for keys Claude gives meaning to: Shift+Enter and Alt+Enter
// (newline), a lone Esc (interrupt), Ctrl+B (background a command; tmux's
// default prefix), and a bracketed paste.
test('keys and pastes reach the application byte for byte', async ({ page }) => {
    // Reads byte by byte with dd until a "q": bash's read would turn CR into LF.
    await typeLine(page, `stty raw -echo; printf '\\e[?2004hREADY\\r\\n'; k=; while b=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \\n'); [ "$b" != 71 ]; do k="$k$b"; done; stty sane; printf '\\e[?2004l'; echo "got=$k"`);
    await waitForText(page, /^READY$/m);

    await page.evaluate(() => {
        window.e2eSent = [];
        window.term.onData(data => window.e2eSent.push(data));
    });
    // Pause between keys like a person would: tmux reads an Esc followed
    // within escape-time by more input as one key.
    for (const key of ['Shift+Enter', 'Alt+Enter', 'Escape', 'Control+b']) {
        await page.keyboard.press(key);
        await page.waitForTimeout(100);
    }
    await page.evaluate(() => window.term.paste('pasted text'));
    await page.waitForTimeout(100);
    const sent = await page.evaluate(() => window.e2eSent.join(''));
    expect(sent, 'xterm.js should bracket the paste').toContain('\x1b[200~pasted text\x1b[201~');
    await page.keyboard.press('q');

    const expected = Buffer.from(sent).toString('hex');
    await waitForText(page, new RegExp(`^got=${expected}$`, 'm'), { message: `application to receive ${JSON.stringify(sent)}` });
});

test('mouse drag selects text in the browser', async ({ page }) => {
    await typeLine(page, 'echo "select-me-$((6 * 7))"');
    await waitForText(page, /^select-me-42$/m);
    const { row, col } = await locateText(page, 'select-me-42');
    const from = await cellCenter(page, { row, col });
    const to = await cellCenter(page, { row, col: col + 'select-me-42'.length - 1 });

    await page.mouse.move(from.x - 2, from.y);
    await page.mouse.down();
    await page.mouse.move(to.x + 2, to.y, { steps: 5 });
    await page.mouse.up();
    expect(await page.evaluate(() => window.term.getSelection())).toBe('select-me-42');
});

// In the alternate screen xterm.js would turn the wheel into arrow keys, which
// Claude reads as prompt history; in the normal screen it scrolls. tmux must
// also scroll with linefeeds for lines to be kept as scrollback at all.
test('the wheel scrolls the browser scrollback', async ({ page }) => {
    // Pace output so tmux renders it incrementally: a single burst can skip
    // frames and leave only its last screen in browser scrollback. This tests
    // linefeed retention and wheel scrolling, not burst redraw scheduling.
    await typeLine(page, 'for batch in $(seq 0 29); do seq $((batch * 10 + 1)) $((batch * 10 + 10)); sleep 0.1; done');
    await waitForText(page, /^300$/m);
    const buffer = await page.evaluate(() => ({ type: window.term.buffer.active.type, baseY: window.term.buffer.active.baseY, rows: window.term.rows }));
    expect(buffer.type).toBe('normal');
    expect(buffer.baseY, 'lines kept in the browser scrollback').toBeGreaterThan(buffer.rows);

    const box = await page.locator('.xterm-screen').boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.wheel(0, -1000);
    await expect.poll(() => page.evaluate(() => {
        const active = window.term.buffer.active;
        return active.viewportY < active.baseY;
    }), { message: 'viewport to scroll up into the scrollback' }).toBe(true);
});
