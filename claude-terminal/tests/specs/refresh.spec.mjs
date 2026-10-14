import { test, expect, openBashShell } from '../lib/fixtures.mjs';
import { bufferText, openTerminal, typeLine, waitForText } from '../lib/terminal.mjs';

const isAlive = async (addon, pid) => addon.exec('kill', '-0', pid).then(() => true, () => false);

// CURRENT BEHAVIOUR, not the desired one. ttyd spawns a new process for every
// WebSocket connection and hangs up the old one when it closes, so reloading
// the page throws away whatever was running (including a Claude session).
//
// The session-persistence change is expected to make this test fail: replace
// it with one asserting that the reloaded page reattaches to the same process
// and shows its existing output.
test('current behaviour: page reload starts a fresh session and ends the previous one', async ({ page, terminalUrl, addon }) => {
    await openTerminal(page, terminalUrl);
    await openBashShell(page);
    await typeLine(page, 'echo "session-pid=$$"');
    const [, pid] = await waitForText(page, /^session-pid=(\d+)$/m);
    expect(await isAlive(addon, pid), `shell ${pid} should be running before the reload`).toBe(true);

    await page.reload();
    await waitForText(page, /Enter your choice/, { message: 'a new session picker after the reload' });
    expect(await bufferText(page), 'reloaded page should not show the previous session').not.toContain(`session-pid=${pid}`);

    await expect.poll(() => isAlive(addon, pid), {
        message: `previous shell ${pid} should exit once its connection closes`,
    }).toBe(false);
});
