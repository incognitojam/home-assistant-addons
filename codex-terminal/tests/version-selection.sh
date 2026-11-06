#!/usr/bin/env bash
# Run only in a disposable add-on container; replaces /usr/local/bin/codex.
set -euo pipefail
# shellcheck disable=SC1090
source <(sed '$d' /run.sh)
bashio::log.info() { :; }
bashio::log.warning() { :; }
bashio::log.error() { :; }

readonly bundled=/usr/local/bin/codex
export NPM_CONFIG_PREFIX=/data/npm
readonly persistent="${NPM_CONFIG_PREFIX}/bin/codex"
mkdir -p "$(dirname "${persistent}")"

fake_codex() {
    rm -f "$1"
    printf '#!/bin/sh\nprintf "codex-cli %s\\n"\n' "$2" > "$1"
    chmod +x "$1"
}

broken_codex() {
    rm -f "$1"
    printf '#!/bin/sh\nexit 1\n' > "$1"
    chmod +x "$1"
}

expect_selected() {
    local description="$1" expected="$2"
    select_codex
    if [ "${CODEX_EXECUTABLE}" != "${expected}" ]; then
        printf 'FAILED: %s: selected %s, expected %s\n' "${description}" "${CODEX_EXECUTABLE}" "${expected}" >&2
        exit 1
    fi
}

fake_codex "${bundled}" 0.167.0
expect_selected "no override" "${bundled}"

fake_codex "${persistent}" 0.168.0
expect_selected "newer override" "${persistent}"

fake_codex "${persistent}" 0.166.0
expect_selected "older override" "${bundled}"

fake_codex "${persistent}" 0.167.0
expect_selected "equal override" "${bundled}"

# Compare numerically, not as text.
fake_codex "${persistent}" 0.1000.0
expect_selected "numerically newer override" "${persistent}"

fake_codex "${persistent}" 0.167.0-alpha.1
expect_selected "prerelease of the bundled version" "${bundled}"

fake_codex "${persistent}" 0.168.0-alpha.1
expect_selected "prerelease of a newer version" "${persistent}"

fake_codex "${persistent}" unknown
expect_selected "unparsable override" "${bundled}"

broken_codex "${persistent}"
expect_selected "broken override" "${bundled}"

rm -f "${persistent}"
ln -s /nonexistent/codex "${persistent}"
expect_selected "dangling override" "${bundled}"

fake_codex "${persistent}" 0.166.0
broken_codex "${bundled}"
expect_selected "broken bundled version keeps a working override" "${persistent}"

rm -f "${persistent}"
if (select_codex) >/dev/null 2>&1; then
    printf 'FAILED: selection succeeded with no working Codex\n' >&2
    exit 1
fi

printf 'Codex version selection test passed.\n'
