import { test, expect } from '../lib/fixtures.mjs';

test('container starts the web terminal and serves the patched page', async ({ addon, terminalUrl }) => {
    expect(await addon.logs()).toMatch(/Starting web terminal/);

    const response = await fetch(terminalUrl);
    expect(response.status, `GET ${terminalUrl}`).toBe(200);
    const html = await response.text();
    // Check a boolean rather than toContain(): the inlined page is ~700KB and
    // would otherwise be printed in full on failure.
    expect(html.includes('id="terminal-input-hints"'), 'index should be the build-time patched ttyd page with terminal-input-hints.js').toBe(true);
});
