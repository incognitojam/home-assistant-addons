import { test, expect } from '../lib/fixtures.mjs';
import { openTerminal } from '../lib/terminal.mjs';

// The iPhone project runs in WebKit and the Pixel project in Chromium, the
// engines behind iOS Safari and Android Chrome. Emulation cannot raise a real
// on-screen keyboard, so this checks the attributes that tell one not to
// autocorrect, autocapitalise or suggest words in the terminal.
test('xterm input has mobile keyboard hints', async ({ page, terminalUrl }) => {
    await openTerminal(page, terminalUrl);
    const input = page.locator('.xterm textarea.xterm-helper-textarea');
    await page.evaluate(() => window.term.focus());

    // xterm.js sets autocorrect, autocapitalize and spellcheck itself;
    // autocomplete="off" comes only from terminal-input-hints.js.
    const hints = { autocomplete: 'off', autocorrect: 'off', autocapitalize: 'off', spellcheck: 'false' };
    for (const [name, value] of Object.entries(hints)) {
        await expect(input, `helper textarea should have ${name}="${value}"`).toHaveAttribute(name, value);
    }
    expect(await input.evaluate(element => element.spellcheck), 'helper textarea spellcheck property').toBe(false);
});
