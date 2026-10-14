import { fileURLToPath } from 'node:url';
import { test as base, expect, chooseSessionPickerOption, openBashShell } from '../lib/fixtures.mjs';
import { docker } from '../lib/container.mjs';
import { bufferText, cellCenter, locateText, openTerminal, screenText, typeLine, waitForText } from '../lib/terminal.mjs';

// Only remote API responses are synthetic: run.sh, ttyd, tmux, and the native
// Claude binary all run normally, with no real credentials or model charges.
const test = base.extend({
    launch: ['auto', { option: true, scope: 'worker' }],
    savedFullscreen: [true, { option: true, scope: 'worker' }],
    addonEnv: [async ({ launch, savedFullscreen }, use) => {
        await use({
            AUTO_LAUNCH_CLAUDE: launch === 'auto' ? 'true' : 'false',
            AUTO_UPDATE_CLAUDE: 'false',
            PERMISSION_MODE: 'default',
            ANTHROPIC_AUTH_TOKEN: 'synthetic-renderer-token',
            ANTHROPIC_BASE_URL: 'http://127.0.0.1:8080',
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: '1',
            ...(savedFullscreen ? { CLAUDE_CODE_NO_FLICKER: '1' } : {}),
            CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN: '0',
        });
    }, { scope: 'worker' }],
    addon: [async ({ addon, savedFullscreen }, use) => {
        // Acknowledge the unrelated auto-mode nudge before testing renderer startup.
        await addon.exec('sh', '-c', `cat > /data/home/.claude.json <<'EOF'
{"hasCompletedOnboarding":true,"hasSeenAutoDefaultNudge":true,"theme":"dark","projects":{"/config":{"hasTrustDialogAccepted":true,"hasCompletedProjectOnboarding":true}}}
EOF
cat > /data/home/.claude/settings.json <<'EOF'
${JSON.stringify({ ...(savedFullscreen ? { tui: 'fullscreen' } : {}), alwaysThinkingEnabled: false, permissions: { defaultMode: 'default' } })}
EOF`);
        // Re-run the actual startup with saved preferences already present.
        await docker('restart', addon.name);
        const mapping = (await docker('port', addon.name, '7681/tcp')).trim().split('\n')[0];
        addon.baseUrl = `http://127.0.0.1:${mapping.slice(mapping.lastIndexOf(':') + 1)}`;
        await addon.waitForHttp({ timeout: 60_000 });
        await docker('cp', fileURLToPath(new URL('../lib/synthetic-anthropic.py', import.meta.url)), `${addon.name}:/synthetic-anthropic.py`);
        await docker('exec', '--detach', addon.name, 'python3', '/synthetic-anthropic.py');
        await expect.poll(() => addon.exec('curl', '-fsS', 'http://127.0.0.1:8080/').catch(() => '')).toBe('{}');
        expect(JSON.parse(await addon.exec('cat', '/data/home/.claude/settings.json')).tui).toBe(savedFullscreen ? 'fullscreen' : undefined);
        await use(addon);
    }, { scope: 'worker' }],
});

test('normal interactive launches keep classic rendering and browser controls', async ({ page, addon, terminalUrl, launch, savedFullscreen }) => {
    await openTerminal(page, terminalUrl);
    if (launch === 'picker') await chooseSessionPickerOption(page, /New interactive session/);
    if (launch === 'manual') {
        await openBashShell(page);
        await typeLine(page, 'claude');
    }
    await waitForText(page, /for shortcuts|Try "/i, { timeout: 30_000 });
    await typeLine(page, '/tui');
    await waitForText(page, /Current renderer:\s*(?:classic|default)\b/i);
    expect(await bufferText(page)).not.toMatch(/Try the new fullscreen renderer/i);

    // Inspect the real launched process, not docker exec's environment.
    const pid = (await addon.exec('pgrep', '-f', '^claude( |$)')).trim();
    const env = await addon.exec('sh', '-c', `tr '\\0' '\\n' < /proc/${pid}/environ`);
    expect(env).toMatch(/^CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1$/m);
    if (savedFullscreen) expect(env).toMatch(/^CLAUDE_CODE_NO_FLICKER=1$/m);
    else expect(env).not.toMatch(/^CLAUDE_CODE_NO_FLICKER=/m);

    await typeLine(page, 'Return the synthetic renderer test response.');
    await waitForText(page, /Synthetic renderer line 080/, { timeout: 30_000 });
    expect(await bufferText(page)).not.toMatch(/Try the new fullscreen renderer/i);
    expect(await page.evaluate(() => ({
        type: window.term.buffer.active.type,
        mouse: window.term.modes.mouseTrackingMode,
    }))).toEqual({ type: 'normal', mouse: 'none' });
    expect((await addon.exec('tmux', 'display-message', '-p', '#{alternate_on}')).trim()).toBe('0');
    expect(JSON.parse(await addon.exec('cat', '/data/home/.claude/settings.json')).tui).toBe(savedFullscreen ? 'fullscreen' : undefined);

    const before = (await addon.exec('pgrep', '-f', '^claude( |$)')).trim();
    await page.reload();
    await page.waitForFunction(() => window.term?.buffer?.active !== undefined);
    await expect.poll(() => screenText(page)).toMatch(/Synthetic renderer line 080/);
    expect((await addon.exec('pgrep', '-f', '^claude( |$)')).trim()).toBe(before);

    const { row, col } = await locateText(page, '  Synthetic renderer line 080');
    const from = await cellCenter(page, { row, col: col + 2 });
    const to = await cellCenter(page, { row, col: col + 28 });
    await page.mouse.move(from.x - 2, from.y);
    await page.mouse.down();
    await page.mouse.move(to.x + 2, to.y, { steps: 5 });
    await page.mouse.up();
    expect(await page.evaluate(() => window.term.getSelection())).toBe('Synthetic renderer line 080');

    const box = await page.locator('.xterm-screen').boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.wheel(0, -1000);
    await expect.poll(() => page.evaluate(() => window.term.buffer.active.viewportY < window.term.buffer.active.baseY)).toBe(true);
    await page.evaluate(() => window.term.scrollToBottom());
    await typeLine(page, '/exit');
    await waitForText(page, /Resume this session with/);
});
