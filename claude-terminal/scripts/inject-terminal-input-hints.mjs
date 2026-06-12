import { readFileSync, writeFileSync } from 'node:fs';

const [, , indexPath, hintsPath, outputPath] = process.argv;

if (!indexPath || !hintsPath || !outputPath) {
    console.error('Usage: inject-terminal-input-hints.mjs <index.html> <hints.js> <output.html>');
    process.exit(2);
}

const html = readFileSync(indexPath, 'utf8');
const hints = readFileSync(hintsPath, 'utf8').trim();

if (hints.toLowerCase().includes('</script')) {
    console.error(`${hintsPath} cannot contain a closing script tag`);
    process.exit(1);
}

const script = `\n<script id="terminal-input-hints">\n${hints}\n</script>\n`;
const closeBody = /<\/body\s*>/i;
const output = closeBody.test(html) ? html.replace(closeBody, `${script}</body>`) : `${html}${script}`;

writeFileSync(outputPath, output);
