// Playwright fixtures for the claude-terminal add-on.
//
// Each worker starts its own container (Docker picks a free host port) and,
// for the `ingress` projects, an ingress-like reverse proxy in front of it.
// Specs choose add-on options with `test.use({ addonEnv: {...} })`; a file
// that changes them gets its own worker and container.

import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { test as base, expect } from '@playwright/test';
import { AddonContainer } from './container.mjs';
import { startIngressProxy } from './ingress-proxy.mjs';
import { bufferText, waitForText, typeLine } from './terminal.mjs';

export const IMAGE = process.env.IMAGE || 'local/claude-terminal:test';

export const test = base.extend({
    // Env overrides read by run.sh's get_addon_option (there is no Supervisor
    // to answer bashio::config). Auto-update is off so tests never download.
    addonEnv: [{ AUTO_LAUNCH_CLAUDE: 'false', AUTO_UPDATE_CLAUDE: 'false' }, { option: true, scope: 'worker' }],
    // 'direct' hits ttyd's published port; 'ingress' goes through the proxy.
    access: ['direct', { option: true, scope: 'worker' }],

    addon: [async ({ addonEnv }, use, workerInfo) => {
        const addon = new AddonContainer({
            image: IMAGE,
            env: addonEnv,
            readyLog: /Starting web terminal/,
            namePrefix: 'claude-terminal-e2e',
        });
        try {
            await addon.start();
            await use(addon);
        } finally {
            const logDir = path.join(workerInfo.project.outputDir, 'container-logs');
            await mkdir(logDir, { recursive: true });
            await writeFile(path.join(logDir, `${addon.name}.log`), await addon.logs());
            await addon.stop();
        }
    }, { scope: 'worker', timeout: 120_000 }],

    ingress: [async ({ addon, access }, use) => {
        if (access !== 'ingress') {
            await use(undefined);
            return;
        }
        const proxy = await startIngressProxy({ target: addon.baseUrl });
        await use(proxy);
        await proxy.close();
    }, { scope: 'worker' }],

    // Every connection attaches to one shared tmux session that outlives the
    // page, so end it before each test to start from the configured launch
    // command rather than whatever the previous test left running.
    terminalUrl: async ({ addon, ingress }, use) => {
        await addon.exec('tmux', 'kill-server').catch(() => {});
        if (ingress) ingress.misses.length = 0;
        await use(ingress ? ingress.url : `${addon.baseUrl}/`);
    },

    // On failure, attach what is needed to debug without re-running: the
    // terminal buffer as text and the container logs so far. Playwright adds
    // the trace and screenshot itself (see playwright.config.mjs).
    failureArtifacts: [async ({ page, addon }, use, testInfo) => {
        await use();
        if (testInfo.status === testInfo.expectedStatus) return;
        const artifacts = {
            'terminal-buffer.txt': await bufferText(page).catch(error => `<could not read terminal buffer: ${error.message}>`),
            'container.log': await addon.logs(),
        };
        for (const [name, body] of Object.entries(artifacts)) {
            const file = testInfo.outputPath(name);
            await writeFile(file, body);
            await testInfo.attach(name, { path: file, contentType: 'text/plain' });
        }
    }, { auto: true }],
});

export { expect };

// Selects a session picker entry by its label rather than its number, so
// renumbering the menu does not break tests.
export async function chooseSessionPickerOption(page, label) {
    await waitForText(page, /Enter your choice/, { message: 'session picker prompt to appear' });
    const pattern = new RegExp(`^\\s*(\\d+)\\)\\s.*${label.source}`, 'im');
    const [, number] = await waitForText(page, pattern, { message: `session picker to list an option matching ${label}` });
    await typeLine(page, number);
}

// Drops from the session picker to bash and waits for the prompt, so typed
// input reaches bash rather than the picker's pre-exec pause.
export async function openBashShell(page) {
    await chooseSessionPickerOption(page, /bash shell/);
    await waitForText(page, /Dropping to bash shell[\s\S]*[#$]$/, { message: 'bash prompt after leaving the session picker' });
}
