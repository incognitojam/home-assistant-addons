import { test, expect, openBashShell } from '../lib/fixtures.mjs';
import { openTerminal, typeLine, waitForText } from '../lib/terminal.mjs';

test('terminal connects and shows the session picker', async ({ page, terminalUrl, ingress }) => {
    await openTerminal(page, terminalUrl);
    await waitForText(page, /Interactive Session Picker/);
    await waitForText(page, /Enter your choice/);

    if (ingress) {
        expect(ingress.misses, 'requests outside the ingress prefix (absolute URLs?)').toEqual([]);
    }
});

test('bash shell from the session picker runs a command', async ({ page, terminalUrl }) => {
    await openTerminal(page, terminalUrl);
    await openBashShell(page);

    // The shell expands the arithmetic, so the expected text only appears in
    // command output, never in the echoed input line.
    await typeLine(page, 'echo "e2e-$((6 * 7))-marker"');
    await waitForText(page, /^e2e-42-marker$/m, { message: 'shell output of the echo command' });
});
