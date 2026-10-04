import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { test } from "node:test";

// Run in a disposable image, with synthetic authentication and no network or model calls.
async function readConfig(userConfig, args = []) {
    assert.ok(process.env.CODEX_HOME, "Set CODEX_HOME to an isolated test directory");
    await mkdir(process.env.CODEX_HOME, { recursive: true });
    const codexHome = await mkdtemp(join(process.env.CODEX_HOME, "approval-test-"));
    const configFile = join(codexHome, "config.toml");
    if (userConfig !== undefined) {
        await writeFile(configFile, userConfig);
    }

    const env = { ...process.env, CODEX_HOME: codexHome };
    execFileSync("codex", ["login", "--with-api-key"], {
        env,
        input: "sk-synthetic-approval-test\n",
        stdio: ["pipe", "ignore", "pipe"],
        timeout: 10_000,
    });
    const child = spawn("codex-auth-launcher", [...args, "app-server", "--stdio"], {
        env,
        stdio: ["pipe", "pipe", "pipe"],
    });
    const closed = new Promise((resolve) => child.once("close", resolve));
    const lines = createInterface({ input: child.stdout });
    let stderr = "";
    child.stderr.on("data", (data) => { stderr += data; });
    let timer;

    try {
        const config = await new Promise((resolve, reject) => {
            timer = setTimeout(() => {
                child.kill("SIGKILL");
                reject(new Error(`Codex config read timed out: ${stderr}`));
            }, 30_000);
            child.on("error", reject);
            child.stdin.on("error", reject);
            child.on("exit", (code) => reject(new Error(`Codex exited (${code}): ${stderr}`)));

            const send = (message) => child.stdin.write(`${JSON.stringify(message)}\n`);
            lines.on("line", (line) => {
                try {
                    const response = JSON.parse(line);
                    if (response.error) {
                        throw new Error(JSON.stringify(response.error));
                    }
                    if (response.id === 1) {
                        send({ method: "initialized" });
                        send({ id: 2, method: "config/read", params: {} });
                    } else if (response.id === 2) {
                        resolve(response.result.config);
                    }
                } catch (error) {
                    reject(error);
                }
            });
            send({
                id: 1,
                method: "initialize",
                params: { clientInfo: { name: "addon-approval-test", version: "1.0.0" } },
            });
        });

        if (userConfig !== undefined) {
            assert.equal(await readFile(configFile, "utf8"), userConfig, "Saved preferences changed");
        }
        return config;
    } finally {
        child.kill("SIGTERM");
        await closed;
        clearTimeout(timer);
        lines.close();
        await rm(codexHome, { recursive: true, force: true });
    }
}

test("fresh state defaults to automatic review inside the workspace sandbox", async () => {
    const config = await readConfig();
    assert.equal(config.approval_policy, "on-request");
    assert.equal(config.approvals_reviewer, "auto_review");
    assert.equal(config.sandbox_mode, "workspace-write");
});

test("unrelated saved settings retain the automatic review defaults", async () => {
    const config = await readConfig('model = "synthetic-test-model"\n');
    assert.equal(config.model, "synthetic-test-model");
    assert.equal(config.approvals_reviewer, "auto_review");
    assert.equal(config.approval_policy, "on-request");
    assert.equal(config.sandbox_mode, "workspace-write");
});

test("a saved manual reviewer overrides the image default", async () => {
    const config = await readConfig('approvals_reviewer = "user"\n');
    assert.equal(config.approvals_reviewer, "user");
    assert.equal(config.approval_policy, "on-request");
    assert.equal(config.sandbox_mode, "workspace-write");
});

test("saved approval and sandbox policies are preserved", async () => {
    const config = await readConfig('approval_policy = "never"\nsandbox_mode = "read-only"\napprovals_reviewer = "user"\n');
    assert.equal(config.approval_policy, "never");
    assert.equal(config.approvals_reviewer, "user");
    assert.equal(config.sandbox_mode, "read-only");
});

test("command-line settings override the image default", async () => {
    const config = await readConfig(undefined, ["-c", 'approvals_reviewer="user"']);
    assert.equal(config.approvals_reviewer, "user");
});
