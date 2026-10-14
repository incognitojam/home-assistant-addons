import { defineConfig, devices } from '@playwright/test';

// Projects:
//   direct / ingress   desktop Chromium, straight to ttyd and via the
//                      ingress-like proxy that serves it under a path prefix
//   iphone / pixel     phone emulation: WebKit for iPhone, Chromium for Pixel
//   claude-launch      AUTO_LAUNCH_CLAUDE=true, checks the real Claude binary
//                      starts; its @network test needs internet access
//
// IMAGE selects the add-on image under test (default local/claude-terminal:test).
const terminalSpecs = ['startup.spec.mjs', 'terminal.spec.mjs', 'refresh.spec.mjs'];

export default defineConfig({
    testDir: './specs',
    globalSetup: './lib/global-setup.mjs',
    outputDir: './test-results',
    timeout: 60_000,
    expect: { timeout: 15_000 },
    fullyParallel: false,
    forbidOnly: Boolean(process.env.CI),
    retries: 0,
    workers: process.env.CI ? 2 : undefined,
    reporter: process.env.CI
        ? [['list'], ['github'], ['html', { open: 'never', outputFolder: './playwright-report' }]]
        : [['list'], ['html', { open: 'never', outputFolder: './playwright-report' }]],
    use: {
        trace: 'retain-on-failure',
        screenshot: 'only-on-failure',
    },
    projects: [
        {
            name: 'direct',
            testMatch: terminalSpecs,
            use: { ...devices['Desktop Chrome'], access: 'direct' },
        },
        {
            name: 'ingress',
            testMatch: terminalSpecs,
            use: { ...devices['Desktop Chrome'], access: 'ingress' },
        },
        {
            name: 'iphone',
            testMatch: 'mobile.spec.mjs',
            use: { ...devices['iPhone 15'], access: 'ingress' },
        },
        {
            name: 'pixel',
            testMatch: 'mobile.spec.mjs',
            use: { ...devices['Pixel 7'], access: 'ingress' },
        },
        {
            name: 'claude-launch',
            testMatch: 'claude-launch.spec.mjs',
            use: { ...devices['Desktop Chrome'], access: 'ingress' },
        },
    ],
});
