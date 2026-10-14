import { test, expect, openBashShell } from '../lib/fixtures.mjs';
import { bufferText, openTerminal, screenText, typeLine, waitForText } from '../lib/terminal.mjs';

const isAlive = async (addon, pid) => addon.exec('kill', '-0', pid).then(() => true, () => false);

// ttyd hangs up its process when the WebSocket closes, but that process is
// only a tmux client: the session it attached to keeps running, and the next
// connection attaches to it again.
test('page reload reattaches to the running session with its output', async ({ page, terminalUrl, addon }) => {
    await openTerminal(page, terminalUrl);
    await openBashShell(page);
    // Enough lines that the first ones have scrolled into tmux's history, so
    // seeing them after the reload means the history was replayed, not just
    // the visible screen redrawn.
    await typeLine(page, 'for i in $(seq 200); do echo "history-line-$i"; done');
    // Wait for the prompt before typing again: while the loop runs, the tty
    // echoes typeahead into its output (such as the "e" of the next "echo").
    await waitForText(page, /^history-line-200\n.*[#$]$/m, { message: 'bash prompt after the loop' });
    await typeLine(page, 'echo "session-pid=$$"');
    const [, pid] = await waitForText(page, /^session-pid=(\d+)$/m);

    await page.reload();
    await waitForText(page, new RegExp(`^session-pid=${pid}$`, 'm'), { message: 'previous output on screen after the reload' });
    expect(await bufferText(page), 'earlier output should be back in the scrollback').toMatch(/^history-line-1$/m);
    expect(await isAlive(addon, pid), `shell ${pid} should survive the reload`).toBe(true);

    await typeLine(page, 'echo "after-reload-pid=$$"');
    await waitForText(page, new RegExp(`^after-reload-pid=${pid}$`, 'm'), { message: 'input reaching the same shell after the reload' });
});

test('two tabs share the same session', async ({ page, terminalUrl }) => {
    await openTerminal(page, terminalUrl);
    await openBashShell(page);

    const other = await page.context().newPage();
    await openTerminal(other, terminalUrl);
    await typeLine(other, 'echo "from-second-tab-$((6 * 7))"');

    await waitForText(other, /^from-second-tab-42$/m);
    await waitForText(page, /^from-second-tab-42$/m, { message: 'output typed in the second tab, shown in the first' });
    await other.close();
});

test('the session follows the browser size', async ({ page, terminalUrl, addon }) => {
    await openTerminal(page, terminalUrl);
    await openBashShell(page);

    for (const size of [{ width: 390, height: 664 }, { width: 1280, height: 720 }]) {
        const before = await page.evaluate(() => window.term.cols);
        await page.setViewportSize(size);
        await expect.poll(() => page.evaluate(() => window.term.cols), { message: `xterm.js to refit at ${size.width}px` }).not.toBe(before);
        const cols = await page.evaluate(() => window.term.cols);
        // ttyd sends the new size asynchronously; wait for tmux to apply it.
        await expect.poll(async () => Number(await addon.exec('tmux', 'display-message', '-p', '#{window_width}')), {
            message: `tmux window to resize to ${cols} columns`,
        }).toBe(cols);
        await typeLine(page, 'echo "size=$(stty size)"');
        await waitForText(page, new RegExp(`^size=\\d+ ${cols}$`, 'm'), { message: `shell to see ${cols} columns at ${size.width}px` });
    }
});

test('exiting ends the session and a reload starts a fresh one', async ({ page, terminalUrl, addon }) => {
    await openTerminal(page, terminalUrl);
    await openBashShell(page);
    await typeLine(page, 'echo "session-pid=$$"');
    const [, pid] = await waitForText(page, /^session-pid=(\d+)$/m);

    await typeLine(page, 'exit');
    await expect.poll(() => isAlive(addon, pid), { message: `shell ${pid} should exit` }).toBe(false);
    // tmux clears the screen as the session ends; the last screen is shown again.
    await expect.poll(() => screenText(page), { message: 'final output still on screen after exit' }).toMatch(new RegExp(`^session-pid=${pid}$`, 'm'));

    await page.reload();
    await waitForText(page, /Enter your choice/, { message: 'a new session picker after the reload' });
    expect(await bufferText(page), 'reloaded page should not show the ended session').not.toContain(`session-pid=${pid}`);
});
