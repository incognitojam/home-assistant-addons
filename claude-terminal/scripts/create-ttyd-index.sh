#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_index="${1:-/tmp/ttyd-default-index.html}"
target_index="${2:-/opt/ttyd-index.html}"
hints_script="${3:-${script_dir}/terminal-input-hints.js}"
probe_port="${TTYD_INDEX_PORT:-17681}"
ttyd_log="$(mktemp)"
ttyd_pid=""

cleanup() {
    if [ -n "$ttyd_pid" ]; then
        if kill -0 "$ttyd_pid" 2>/dev/null; then
            kill "$ttyd_pid" 2>/dev/null || true
        fi
        wait "$ttyd_pid" 2>/dev/null || true
    fi
    rm -f "$ttyd_log" "$source_index"
}
trap cleanup EXIT

ttyd --port "$probe_port" --interface 127.0.0.1 sh -c 'sleep 60' >"$ttyd_log" 2>&1 &
ttyd_pid="$!"

for _ in $(seq 1 50); do
    if curl -fsSL "http://127.0.0.1:${probe_port}/" -o "$source_index"; then
        mkdir -p "$(dirname "$target_index")"
        node "${script_dir}/inject-terminal-input-hints.mjs" "$source_index" "$hints_script" "$target_index"
        chmod 644 "$target_index"
        exit 0
    fi
    sleep 0.1
done

echo "Failed to capture ttyd index from local build server" >&2
cat "$ttyd_log" >&2 || true
exit 1
