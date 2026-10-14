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

# A second boot must neither copy the seed again nor reset a managed update.
inode=$(stat -c %i "$seed")
init_environment
[ "$(stat -c %i "$seed")" = "$inode" ]

# Exact legacy fallback migration reuses an existing valid downloaded slot.
rm "$launcher"
ln -s /root/.local/bin/claude "$launcher"
init_environment
[ "$(readlink "$launcher")" = "$seed" ]
[ "$(stat -c %i "$seed")" = "$inode" ]
[ "$(claude --version)" = "$version_output" ]
# Repeat with an absent seed to exercise the actual legacy copy path.
rm "$launcher" "$seed"
ln -s /root/.local/bin/claude "$launcher"
init_environment
[ "$(readlink "$launcher")" = "$seed" ]
cmp "$bundled" "$seed"
doctor=$(timeout 30 claude doctor 2>&1)
[[ "$doctor" == *"Running: native ($version)"* ]]
[[ "$doctor" == *"Path: $seed"* ]]
[[ "$doctor" != *'not created by the native installer'* ]]
[[ "$doctor" != *'custom launcher'* ]]
printf 'Exact legacy fallback migrated; real Claude doctor recognizes native management.\n'

# Offline fixture models the result of an upstream update; it does not test
# the upstream download/relink code. Keep a cached version unselected on migration.
updated="$XDG_DATA_HOME/claude/versions/0.0.0-test-update"
printf '#!/bin/sh\necho "0.0.0-test-update (synthetic)"\n' > "$updated"
chmod +x "$updated"
rm "$launcher"
ln -s /root/.local/bin/claude "$launcher"
init_environment
[ "$(readlink "$launcher")" = "$seed" ]
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

# Preserve intentional executables, custom links, and broken custom links.
rm "$launcher"
printf '#!/bin/sh\necho synthetic-wrapper\n' > "$launcher"
chmod +x "$launcher"
init_environment
[ ! -L "$launcher" ]
[ "$(claude --version)" = synthetic-wrapper ]
mv "$launcher" /data/synthetic-custom-claude
ln -s /data/synthetic-custom-claude "$launcher"
init_environment
[ "$(readlink "$launcher")" = /data/synthetic-custom-claude ]
[ "$(claude --version)" = synthetic-wrapper ]
rm "$launcher"
ln -s /data/synthetic-missing-launcher "$launcher"
init_environment
[ "$(readlink "$launcher")" = /data/synthetic-missing-launcher ]
printf 'Custom executable and custom links (including broken links) preserved.\n'

# Bootstrap failures leave the old launcher and existing slots untouched.
rm "$launcher"
ln -s /root/.local/bin/claude "$launcher"
rm "$seed"
printf 'invalid downloaded binary\n' > "$seed"
if bootstrap_claude_launcher; then
    echo 'Unexpected success with invalid seed' >&2
    exit 1
fi
[ "$(cat "$seed")" = 'invalid downloaded binary' ]
[ "$(readlink "$launcher")" = /root/.local/bin/claude ]
rm "$seed"
ln -s "$bundled" "$seed"
if bootstrap_claude_launcher; then
    echo 'Unexpected success with chained seed' >&2
    exit 1
fi
[ "$(readlink "$seed")" = "$bundled" ]
rm "$seed"
printf '#!/bin/sh\necho "0.0.0 (Claude Code)"\n' > "$seed"
chmod +x "$seed"
if bootstrap_claude_launcher; then
    echo 'Unexpected success with mismatched seed version' >&2
    exit 1
fi
[ "$(readlink "$launcher")" = /root/.local/bin/claude ]
rm "$seed"

# Alter only this disposable image's bundled launcher to test missing/malformed
# sources. A fresh missing source must also make actual init fail, not continue.
rm /root/.local/bin/claude
ln -s /data/synthetic-missing-binary /root/.local/bin/claude
if bootstrap_claude_launcher; then
    echo 'Unexpected success with missing bundled binary' >&2
    exit 1
fi
[ "$(readlink "$launcher")" = /root/.local/bin/claude ]
rm "$launcher"
if bash -c 'source /usr/lib/bashio/bashio.sh; source <(sed '\''$d'\'' /run.sh); init_environment'; then
    echo 'Unexpected init success with missing bundled binary' >&2
    exit 1
fi
[ ! -e "$launcher" ] && [ ! -L "$launcher" ]
rm /root/.local/bin/claude
printf '#!/bin/sh\necho malformed-version\n' > /root/.local/bin/claude
chmod +x /root/.local/bin/claude
if bootstrap_claude_launcher; then
    echo 'Unexpected success with malformed bundled version' >&2
    exit 1
fi
[ ! -e "$launcher" ] && [ ! -L "$launcher" ]
[ -z "$(find "$XDG_DATA_HOME/claude/versions" -name '.bootstrap-*' -print)" ]
printf 'Invalid/missing binaries fail safely without replacing existing files.\n'
printf 'Claude native launcher tests passed.\n'
