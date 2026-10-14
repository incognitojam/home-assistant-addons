// Start and stop an add-on container for a test worker.
//
// Nothing here is specific to claude-terminal: the image, environment, ready
// log line and container port are all parameters, so the same helper can drive
// other ttyd-based add-ons (e.g. codex-terminal).

import { execFile } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export async function docker(...args) {
    const { stdout } = await execFileAsync('docker', args, { maxBuffer: 64 * 1024 * 1024 });
    return stdout;
}

export async function assertImageExists(image) {
    try {
        await docker('image', 'inspect', image);
    } catch {
        throw new Error(
            `Docker image "${image}" not found. Build it first, or set IMAGE to an existing tag, e.g.\n` +
            `  docker build --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.22 -t ${image} ./claude-terminal`,
        );
    }
}

export class AddonContainer {
    constructor({ image, env = {}, containerPort = 7681, readyLog, namePrefix = 'addon-e2e' }) {
        this.image = image;
        this.env = env;
        this.containerPort = containerPort;
        this.readyLog = readyLog;
        this.name = `${namePrefix}-${randomBytes(4).toString('hex')}`;
        this.baseUrl = undefined;
    }

    async start({ timeout = 60_000 } = {}) {
        const envArgs = Object.entries(this.env).flatMap(([key, value]) => ['--env', `${key}=${value}`]);
        // Publishing to an empty host port lets Docker pick a free one, so
        // parallel workers and other local containers never clash.
        await docker(
            'run', '--detach', '--name', this.name,
            '--publish', `127.0.0.1::${this.containerPort}`,
            ...envArgs,
            this.image,
        );

        const mapping = (await docker('port', this.name, `${this.containerPort}/tcp`)).trim().split('\n')[0];
        const hostPort = mapping.slice(mapping.lastIndexOf(':') + 1);
        this.baseUrl = `http://127.0.0.1:${hostPort}`;

        await this.waitForLog(this.readyLog, { timeout });
        await this.waitForHttp({ timeout });
    }

    async logs() {
        try {
            const { stdout, stderr } = await execFileAsync('docker', ['logs', this.name], { maxBuffer: 64 * 1024 * 1024 });
            return stdout + stderr;
        } catch (error) {
            return `<could not read logs for ${this.name}: ${error.message}>`;
        }
    }

    async exec(...command) {
        return docker('exec', this.name, ...command);
    }

    async waitForLog(pattern, { timeout }) {
        const deadline = Date.now() + timeout;
        while (Date.now() < deadline) {
            const logs = await this.logs();
            if (pattern.test(logs)) return logs;
            const state = (await docker('inspect', '--format', '{{.State.Status}}', this.name)).trim();
            if (state !== 'running') {
                throw new Error(`Container ${this.name} is ${state} before logging ${pattern}.\n--- logs ---\n${logs}`);
            }
            await delay(250);
        }
        throw new Error(`Timed out after ${timeout}ms waiting for ${pattern} in ${this.name} logs.\n--- logs ---\n${await this.logs()}`);
    }

    // The ready log line is printed just before `exec ttyd`, so poll until
    // ttyd is actually accepting connections.
    async waitForHttp({ timeout }) {
        const deadline = Date.now() + timeout;
        let lastError;
        while (Date.now() < deadline) {
            try {
                const response = await fetch(`${this.baseUrl}/`);
                if (response.ok) return;
                lastError = new Error(`HTTP ${response.status}`);
            } catch (error) {
                lastError = error;
            }
            await delay(250);
        }
        throw new Error(`Timed out waiting for ${this.baseUrl}/ (${lastError?.message})`);
    }

    async stop() {
        await docker('rm', '--force', '--volumes', this.name).catch(() => {});
    }
}

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
