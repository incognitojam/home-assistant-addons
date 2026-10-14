#!/usr/bin/env bash
# Run only in a disposable add-on container, offline, with synthetic /data.
set -euo pipefail
# shellcheck disable=SC1091
source /usr/lib/bashio/bashio.sh
# shellcheck disable=SC1090
source <(sed '$d' /run.sh)
export AUTO_UPDATE_CLAUDE=false

init_environment
launcher="$HOME/.local/bin/claude"
bundled=$(readlink -f /root/.local/bin/claude)
version_output=$("$bundled" --version)
version=${version_output%% *}
seed="$XDG_DATA_HOME/claude/versions/$version"
[ "$(readlink "$launcher")" = "$seed" ]
[ -f "$seed" ] && [ ! -L "$seed" ]
cmp "$bundled" "$seed"
[ "$(claude --version)" = "$version_output" ]
[ "$DISABLE_AUTOUPDATER" = 1 ]
printf 'Fresh bootstrap runs real Claude %s from a direct persistent link.\n' "$version"

# The real binary must recognize the launcher as native-managed, offline.
doctor=$(timeout 30 claude doctor 2>&1)
printf '%s\n' "$doctor"
[[ "$doctor" == *"Running: native ($version)"* ]]
[[ "$doctor" == *"Path: $seed"* ]]
[[ "$doctor" != *'not created by the native installer'* ]]
[[ "$doctor" != *'custom launcher'* ]]
[[ "$doctor" == *'DISABLE_AUTOUPDATER'* ]]

# A second boot must not copy the seed again.
inode=$(stat -c %i "$seed")
init_environment
[ "$(stat -c %i "$seed")" = "$inode" ]

# Migration seeds the bundled version, leaving a newer cached version unselected.
# This offline fixture models an update; it does not test upstream download/relink.
updated="$XDG_DATA_HOME/claude/versions/0.0.0-test-update"
printf '#!/bin/sh\necho "0.0.0-test-update (synthetic)"\n' > "$updated"
chmod +x "$updated"
rm "$launcher" "$seed"
ln -s /root/.local/bin/claude "$launcher"
init_environment
[ "$(readlink "$launcher")" = "$seed" ]
cmp "$bundled" "$seed"
[ "$(claude --version)" = "$version_output" ]
[ "$DISABLE_AUTOUPDATER" = 1 ]
printf 'Exact legacy fallback migrated to the bundled version.\n'

# A managed update survives initialization under either auto-update preference.
ln -sfn "$updated" "$launcher"
init_environment
[ "$(readlink "$launcher")" = "$updated" ]
[ "$(claude --version)" = '0.0.0-test-update (synthetic)' ]
[ "$DISABLE_AUTOUPDATER" = 1 ]
export AUTO_UPDATE_CLAUDE=true
init_environment
[ "$(readlink "$launcher")" = "$updated" ]
[ -z "${DISABLE_AUTOUPDATER+x}" ]
printf 'Managed update survives boots with auto-updates disabled and enabled.\n'

# Preserve an intentional custom launcher.
printf '#!/bin/sh\necho synthetic-wrapper\n' > /data/synthetic-custom-claude
chmod +x /data/synthetic-custom-claude
ln -sfn /data/synthetic-custom-claude "$launcher"
init_environment
[ "$(readlink "$launcher")" = /data/synthetic-custom-claude ]
[ "$(claude --version)" = synthetic-wrapper ]
printf 'Custom launcher preserved.\n'

# An invalid seed must leave both the original file and legacy launcher untouched.
ln -sfn /root/.local/bin/claude "$launcher"
rm "$seed"
printf 'invalid downloaded binary\n' > "$seed"
if bootstrap_claude_launcher; then
    echo 'Unexpected success with invalid seed' >&2
    exit 1
fi
[ "$(cat "$seed")" = 'invalid downloaded binary' ]
[ "$(readlink "$launcher")" = /root/.local/bin/claude ]
[ -z "$(find "$XDG_DATA_HOME/claude/versions" -name '.bootstrap-*' -print)" ]
printf 'Invalid seed fails safely without replacing existing files.\n'
printf 'Claude native launcher tests passed.\n'
