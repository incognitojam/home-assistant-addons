#!/usr/bin/env node
// Install the system libraries Playwright's downloaded browsers fail to load
// without, and nothing else.
//
// `playwright install-deps` installs a fixed package list that includes fonts,
// Xvfb and GStreamer codecs these tests don't use, and on hosted runners that
// apt download can take minutes. Instead, this runs `ldd` on every executable
// and shared library in the browser directories and maps each missing library
// to a package with Playwright's own table for this distribution, or failing
// that Debian's package naming policy. Installing a package can also satisfy
// other missing libraries through its dependencies, so it checks again
// afterwards. If libraries are still missing, it falls back to
// `playwright install-deps`.
//
// Usage, from the directory that depends on Playwright:
//   node install-browser-libraries.mjs <browser>...
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';

const browsers = process.argv.slice(2);
const browsersPath = process.env.PLAYWRIGHT_BROWSERS_PATH || path.join(os.homedir(), '.cache', 'ms-playwright');
// chromium --only-shell installs chromium_headless_shell-<revision>.
const prefixes = browsers.map(browser => browser === 'chromium' ? 'chromium_headless_shell-' : `${browser}-`);

function run(command, args, options = {}) {
    const result = spawnSync(command, args, { encoding: 'utf8', ...options });
    if (result.error)
        throw result.error;
    return result;
}

function isElf(file) {
    const fd = fs.openSync(file, 'r');
    try {
        const magic = Buffer.alloc(4);
        return fs.readSync(fd, magic, 0, 4, 0) === 4 && magic.toString('latin1') === '\x7fELF';
    } finally {
        fs.closeSync(fd);
    }
}

function elfFiles(dir) {
    const files = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const file = path.join(dir, entry.name);
        if (entry.isDirectory())
            files.push(...elfFiles(file));
        else if (entry.isFile() && isElf(file))
            files.push(file);
    }
    return files;
}

function missingLibraries() {
    const roots = fs.readdirSync(browsersPath)
        .filter(name => prefixes.some(prefix => name.startsWith(prefix)))
        .map(name => path.join(browsersPath, name));
    if (roots.length !== browsers.length)
        throw new Error(`Expected ${browsers.join(', ')} in ${browsersPath}, found ${roots.map(root => path.basename(root)).join(', ') || 'nothing'}`);
    const files = roots.flatMap(elfFiles);
    // Browsers bundle some of their own libraries; let ldd find them, as
    // Playwright's launch-time check does.
    const LD_LIBRARY_PATH = [...new Set(files.map(file => path.dirname(file)))].join(':');
    const missing = new Set();
    for (const file of files) {
        const { status, stdout } = run('ldd', [file], { env: { ...process.env, LD_LIBRARY_PATH } });
        if (status !== 0)
            continue;
        for (const line of stdout.split('\n')) {
            const match = /^\s*(\S+) => not found$/.exec(line);
            if (match)
                missing.add(match[1]);
        }
    }
    return [...missing].sort();
}

// Playwright keeps its library-to-package table inside its bundle rather than
// exporting it. Read the entry for this distribution, which install-deps uses.
function libraryPackages() {
    const require = createRequire(path.join(process.cwd(), 'package.json'));
    const bundle = fs.readFileSync(require.resolve('playwright-core/lib/coreBundle'), 'utf8');
    const osRelease = fs.readFileSync('/etc/os-release', 'utf8');
    const id = /^ID=(.*)$/m.exec(osRelease)?.[1];
    const version = /^VERSION_ID="?([^"\n]*)/m.exec(osRelease)?.[1];
    // The arm64 entries copy their x64 counterparts.
    const platform = `${id}${version}-x64`;
    const start = bundle.indexOf(`"${platform}": {`);
    const table = start === -1 ? null : /lib2package: \{([^}]*)\}/.exec(bundle.slice(start));
    if (!table)
        return {};
    return Object.fromEntries([...table[1].matchAll(/"([^"]+)": "([^"]+)"/g)].map(match => match.slice(1)));
}

// Debian names a library's package after its soname: libfoo.so.3 is in
// libfoo3, libfoo-1.0.so.0 in libfoo-1.0-0, with a t64 suffix on packages
// rebuilt for 64-bit time_t. Used for libraries Playwright's table lacks,
// and only when apt knows the package.
function policyPackage(library) {
    const match = /^(.+)\.so\.(\d+)/.exec(library);
    if (!match)
        return undefined;
    const base = match[1].toLowerCase().replaceAll('_', '-');
    const name = /\d$/.test(base) ? `${base}-${match[2]}` : `${base}${match[2]}`;
    return [`${name}t64`, name].find(candidate => run('apt-cache', ['show', candidate]).status === 0);
}

function sudo(args) {
    const [command, ...rest] = process.getuid() === 0 ? args : ['sudo', ...args];
    const { status } = run(command, rest, { stdio: 'inherit' });
    if (status !== 0)
        throw new Error(`${args.join(' ')} exited with status ${status}`);
}

const table = libraryPackages();
for (let attempt = 1; attempt <= 3; attempt++) {
    const missing = missingLibraries();
    if (!missing.length) {
        console.log('No system libraries missing.');
        process.exit(0);
    }
    console.log(`Missing libraries: ${missing.join(' ')}`);
    if (attempt === 3)
        break;
    if (attempt === 1)
        sudo(['apt-get', 'update']);
    const packages = [...new Set(missing.map(library => table[library] ?? policyPackage(library)).filter(Boolean))].sort();
    if (!packages.length)
        break;
    console.log(`Installing: ${packages.join(' ')}`);
    sudo(['apt-get', 'install', '-y', '--no-install-recommends', ...packages]);
}

console.log('Some libraries are still missing; falling back to playwright install-deps.');
const { status } = run('npx', ['playwright', 'install-deps', ...browsers], { stdio: 'inherit' });
process.exit(status ?? 1);
