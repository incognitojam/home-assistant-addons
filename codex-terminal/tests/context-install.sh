#!/usr/bin/env bash
# Run only in a disposable add-on container with synthetic /data and /config.
set -euo pipefail
# shellcheck disable=SC1090
source <(sed '$d' /run.sh)
bashio::log.info() { printf '%s\n' "$*"; }
bashio::log.warning() { printf '%s\n' "$*"; }
mkdir -p "$CODEX_HOME" /config
install_codex_context
cmp /opt/home-assistant-context.md "$CODEX_HOME/AGENTS.md"
[ ! -e /config/AGENTS.md ]
first_hash=$(sha256sum "$CODEX_HOME/AGENTS.md")
install_codex_context
[ "$first_hash" = "$(sha256sum "$CODEX_HOME/AGENTS.md")" ]

# An unchanged previously managed global copy gets updated.
printf 'synthetic previous bundled context\n' > "$CODEX_HOME/AGENTS.md"
sha256sum "$CODEX_HOME/AGENTS.md" | cut -d ' ' -f1 > "$CODEX_HOME/home-assistant-context.sha256"
install_codex_context
cmp /opt/home-assistant-context.md "$CODEX_HOME/AGENTS.md"

printf 'synthetic user global instructions\n' > "$CODEX_HOME/AGENTS.md"
install_codex_context
[ "$(cat "$CODEX_HOME/AGENTS.md")" = 'synthetic user global instructions' ]
rm "$CODEX_HOME/home-assistant-context.sha256"
install_codex_context
[ "$(cat "$CODEX_HOME/AGENTS.md")" = 'synthetic user global instructions' ]

# The legacy stamp recognizes an installed copy even without a built-in hash.
printf 'synthetic stamped legacy context\n' > /config/AGENTS.md
sha256sum /config/AGENTS.md | cut -d ' ' -f1 > "$CODEX_HOME/AGENTS.md.sha256"
install_codex_context
[ ! -e /config/AGENTS.md ]
[ ! -e "$CODEX_HOME/AGENTS.md.sha256" ]

printf 'synthetic legacy context\n' > /config/AGENTS.md
sha256sum /config/AGENTS.md | cut -d ' ' -f1 > "$CODEX_HOME/AGENTS.md.sha256"
printf 'user edit\n' >> /config/AGENTS.md
legacy_hash=$(sha256sum /config/AGENTS.md)
install_codex_context
[ "$legacy_hash" = "$(sha256sum /config/AGENTS.md)" ]
[ ! -e "$CODEX_HOME/AGENTS.md.sha256" ]
install_codex_context
[ "$legacy_hash" = "$(sha256sum /config/AGENTS.md)" ]

rm /config/AGENTS.md "$CODEX_HOME/AGENTS.md"
ln -s /opt/home-assistant-context.md /config/AGENTS.md
ln -s /opt/home-assistant-context.md "$CODEX_HOME/AGENTS.md"
install_codex_context
[ -L /config/AGENTS.md ]
[ -L "$CODEX_HOME/AGENTS.md" ]
printf 'Codex context installation tests passed.\n'
