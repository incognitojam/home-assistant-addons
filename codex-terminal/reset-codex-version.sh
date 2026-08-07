#!/usr/bin/env bash

set -euo pipefail

readonly npm_prefix="${NPM_CONFIG_PREFIX:-/data/npm}"
readonly persistent_package="${npm_prefix}/lib/node_modules/@openai/codex"
readonly persistent_codex="${npm_prefix}/bin/codex"

if [ ! -e "${persistent_package}" ] && [ ! -e "${persistent_codex}" ]; then
    echo "No persistent Codex override is installed."
else
    echo "Removing the persistent Codex override from ${npm_prefix}..."
    npm uninstall \
        --global \
        --prefix "${npm_prefix}" \
        --no-audit \
        --no-fund \
        @openai/codex
fi

if [ -x /usr/local/bin/codex ]; then
    echo "Bundled Codex fallback: $(/usr/local/bin/codex --version)"
fi
echo "New Codex sessions will use the version bundled with the app image."
