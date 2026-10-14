import { test, expect, chooseSessionPickerOption } from '../lib/fixtures.mjs';
import { openTerminal, typeLine, waitForText } from '../lib/terminal.mjs';

// Deterministic offline relink fixture: tests selection and session lifecycle,
// not Claude's upstream updater or an authenticated Claude /exit command.
test('a relinked native launcher takes effect after exit and reconnect', async ({ page, terminalUrl, addon }) => {
    const launcher = '/data/home/.local/bin/claude';
    const original = (await addon.exec('readlink', launcher)).trim();
    expect(original).toMatch(/^\/data\/\.local\/share\/claude\/versions\//);
    const versions = '/data/.local/share/claude/versions';
    const fixture = label => `#!/bin/bash
printf 'synthetic-launch=${label} pid=%s\\n' "$$"
while IFS= read -r line; do
    [ "$line" = /exit ] && exit 0
done
`;
    try {
        for (const label of ['before', 'after']) {
            const file = `${versions}/0.0.0-test-${label}`;
            await addon.exec('sh', '-c', 'printf "%s" "$1" > "$2" && chmod +x "$2"', 'sh', fixture(label), file);
        }
        await addon.exec('ln', '-sfn', `${versions}/0.0.0-test-before`, launcher);
        await openTerminal(page, terminalUrl);
        await chooseSessionPickerOption(page, /New interactive session/);
        const [, pid] = await waitForText(page, /^synthetic-launch=before pid=(\d+)$/m);
        await addon.exec('ln', '-sfn', `${versions}/0.0.0-test-after`, launcher);

        await page.reload();
        await waitForText(page, new RegExp(`^synthetic-launch=before pid=${pid}$`, 'm'));
        await addon.exec('kill', '-0', pid);
        await typeLine(page, '/exit');
        await expect.poll(() => addon.exec('kill', '-0', pid).then(() => true, () => false)).toBe(false);
        await expect.poll(() => addon.exec('tmux', 'has-session', '-t', '=claude').then(() => true, () => false)).toBe(false);

        await page.reload();
        await chooseSessionPickerOption(page, /New interactive session/);
        const [, nextPid] = await waitForText(page, /^synthetic-launch=after pid=(\d+)$/m);
        expect(nextPid).not.toBe(pid);
    } finally {
        await addon.exec('tmux', 'kill-server').catch(() => {});
        await addon.exec('ln', '-sfn', original, launcher);
        await addon.exec('rm', '-f', `${versions}/0.0.0-test-before`, `${versions}/0.0.0-test-after`);
    }
});
