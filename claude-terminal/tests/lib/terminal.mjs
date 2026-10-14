// Helpers for driving the ttyd web terminal through its xterm.js instance.
//
// ttyd exposes the Terminal as `window.term`; reading `term.buffer.active`
// gives exactly what the user sees (plus scrollback), independent of the
// renderer. All waits poll the buffer with a timeout instead of sleeping.

import { expect } from '@playwright/test';

export async function bufferText(page) {
    return page.evaluate(() => {
        const buffer = window.term?.buffer?.active;
        if (!buffer) return '';
        const lines = [];
        for (let i = 0; i < buffer.length; i++) {
            lines.push((buffer.getLine(i)?.translateToString(true) ?? '').trimEnd());
        }
        // Trimmed so `$` in patterns means the end of the visible text, even
        // with the cursor after a prompt's trailing space.
        return lines.join('\n').trimEnd();
    });
}

// Waits until the terminal buffer matches `pattern` and returns the match.
// On timeout the assertion message includes the full buffer.
export async function waitForText(page, pattern, { timeout = 15_000, message } = {}) {
    let match;
    await expect.poll(async () => {
        match = pattern.exec(await bufferText(page));
        return match !== null;
    }, {
        timeout,
        message: message ?? `terminal buffer to match ${pattern}`,
    }).toBe(true).catch(async error => {
        error.message += `\n--- terminal buffer ---\n${await bufferText(page)}\n--- end buffer ---`;
        throw error;
    });
    return match;
}

// Loads the terminal page and waits for the WebSocket session to start
// producing output.
export async function openTerminal(page, url) {
    await page.goto(url);
    await expect(page.locator('.xterm')).toBeVisible();
    await page.waitForFunction(() => window.term?.buffer?.active !== undefined);
    await waitForText(page, /\S/, { message: 'terminal to render any output from the session' });
}

// Types into the terminal through the real keyboard path (xterm's helper
// textarea), the same way a user's keystrokes reach ttyd.
export async function typeLine(page, text) {
    await page.evaluate(() => window.term.focus());
    await page.keyboard.type(text);
    await page.keyboard.press('Enter');
}

// Returns the viewport row of the first on-screen line that starts with
// `text` (so command output, not the echoed command), and its column 0.
export async function locateText(page, text) {
    const row = await page.evaluate(prefix => {
        const buffer = window.term.buffer.active;
        for (let row = 0; row < window.term.rows; row++) {
            if (buffer.getLine(buffer.viewportY + row)?.translateToString(true).startsWith(prefix)) return row;
        }
        return -1;
    }, text);
    expect(row, `a line starting with "${text}" should be on screen`).toBeGreaterThanOrEqual(0);
    return { row, col: 0 };
}

// Page coordinates of the centre of a viewport cell.
export async function cellCenter(page, { row, col }) {
    return page.evaluate(({ row, col }) => {
        const box = document.querySelector('.xterm-screen').getBoundingClientRect();
        const width = box.width / window.term.cols;
        const height = box.height / window.term.rows;
        return { x: box.left + (col + 0.5) * width, y: box.top + (row + 0.5) * height };
    }, { row, col });
}

// Only the lines currently on screen, without the scrollback.
export async function screenText(page) {
    return page.evaluate(() => {
        const buffer = window.term.buffer.active;
        const lines = [];
        for (let row = 0; row < window.term.rows; row++) {
            lines.push((buffer.getLine(buffer.viewportY + row)?.translateToString(true) ?? '').trimEnd());
        }
        return lines.join('\n').trimEnd();
    });
}
