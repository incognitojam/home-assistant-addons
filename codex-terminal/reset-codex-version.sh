#!/usr/bin/env bash

set -euo pipefail

readonly npm_prefix="${NPM_CONFIG_PREFIX:-/data/npm}"
readonly persistent_package="${npm_prefix}/lib/node_modules/@openai/codex"
readonly persistent_codex="${npm_prefix}/bin/codex"

if [ "${npm_prefix}" != "/data/npm" ]; then
    echo "Refusing to reset unexpected npm prefix: ${npm_prefix}" >&2
    exit 1
fi

if [ ! -e "${persistent_package}" ] \
    && [ ! -L "${persistent_package}" ] \
    && [ ! -e "${persistent_codex}" ] \
    && [ ! -L "${persistent_codex}" ]; then
    echo "No persistent Codex override is installed."
else
    echo "Removing the persistent Codex override from ${npm_prefix}..."
    if ! /usr/bin/npm uninstall \
        --global \
        --prefix "${npm_prefix}" \
        --no-audit \
        --no-fund \
        @openai/codex; then
        echo "npm could not cleanly uninstall Codex; removing the known package paths." >&2
    fi

    /bin/rm -rf -- "${persistent_package}"
    /bin/rm -f -- "${persistent_codex}"

    if [ -e "${persistent_package}" ] \
        || [ -L "${persistent_package}" ] \
        || [ -e "${persistent_codex}" ] \
        || [ -L "${persistent_codex}" ]; then
        echo "Failed to remove the persistent Codex override." >&2
        exit 1
    fi
fi

if [ -x /usr/local/bin/codex ]; then
    echo "Bundled Codex fallback: $(/usr/local/bin/codex --version)"
fi
echo "New Codex sessions will use the version bundled with the app image."
