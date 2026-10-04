#!/usr/bin/env bash

# Run in a disposable add-on container with empty state and no network access.
set -euo pipefail

: "${CODEX_HOME:?Set CODEX_HOME to an isolated test directory}"
mkdir -p "${HOME}" "${CODEX_HOME}"

cleanup() {
    timeout 15 codex app-server daemon stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

timeout 60 codex app-server daemon start | jq --exit-status '
    if .status == "started" then . else error("Codex daemon did not start") end
'

timeout 15 codex app-server daemon version | jq --exit-status '
    if .status == "running" and .cliVersion == .appServerVersion then .
    else error("Codex daemon is not running the bundled CLI version") end
'

timeout 15 codex app-server daemon stop | jq --exit-status '
    if .status == "stopped" then . else error("Codex daemon did not stop") end
'
trap - EXIT

printf 'Codex daemon startup test passed.\n'
