import { test } from '../lib/fixtures.mjs';
import { openTerminal, waitForText } from '../lib/terminal.mjs';

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
