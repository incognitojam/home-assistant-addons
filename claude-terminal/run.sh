#!/usr/bin/with-contenv bashio

# Enable strict error handling
set -e
set -o pipefail

# Read an add-on option with a robust fallback.
#
# In a real Home Assistant install, options come from the Supervisor API via
# bashio::config. Two things make that brittle outside of production:
#   1. Running the image directly (local testing) has no Supervisor, so
#      bashio::config returns an empty string and silently drops the default.
#   2. A transient Supervisor API failure would do the same in production.
#
# This helper lets an env-var override take precedence (handy for local testing,
# e.g. `docker run -e AUTO_LAUNCH_CLAUDE=true ...`) and guarantees the documented
# default is used when the option cannot be read at all.
get_addon_option() {
    local key="$1"
    local default="$2"
    local override="${3:-}"
    local value

    if [ -n "$override" ]; then
        echo "$override"
        return 0
    fi

    value=$(bashio::config "$key" "$default" 2>/dev/null) || true
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        value="$default"
    fi
    echo "$value"
}

# Claude's native updater only manages a direct link into its versions directory.
# Seed the image binary once; a link through /root is treated as a custom launcher
# and is deliberately left unchanged by the updater, even after a download.
bootstrap_claude_launcher() {
    local launcher="$HOME/.local/bin/claude"
    local bundled="/root/.local/bin/claude"
    local versions="$XDG_DATA_HOME/claude/versions"
    local resolved version_output version seed tmp

    # Only migrate the exact fallback created by older add-on versions. All
    # other launchers (including broken custom links) belong to the user.
    if [ -e "$launcher" ] || [ -L "$launcher" ]; then
        if [ ! -L "$launcher" ] || [ "$(readlink "$launcher")" != "$bundled" ]; then
            bashio::log.info "Using existing Claude launcher at $launcher"
            return 0
        fi
    fi

    if ! resolved=$(readlink -f "$bundled") || [ ! -f "$resolved" ] || [ ! -x "$resolved" ] \
        || ! version_output=$(timeout 15 "$resolved" --version); then
        bashio::log.error "Cannot run bundled Claude at $bundled; check the add-on image and restart"
        return 1
    fi
    if [[ "$version_output" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\ \(Claude\ Code\)$ ]]; then
        version="${BASH_REMATCH[1]}"
    else
        bashio::log.error "Cannot identify bundled Claude version; leaving $launcher unchanged"
        return 1
    fi
    seed="$versions/$version"

    if ! mkdir -p "$versions" "$HOME/.local/bin"; then
        bashio::log.error "Cannot create Claude installation directories; check free space and permissions in /data"
        return 1
    fi
    if [ ! -e "$seed" ] && [ ! -L "$seed" ]; then
        if ! tmp=$(mktemp "$versions/.bootstrap-XXXXXX"); then
            bashio::log.error "Cannot seed Claude $version; check free space and permissions in /data"
            return 1
        fi
        # Rename within the destination directory so partial copies are never
        # selected. Never overwrite a version already downloaded by Claude.
        if ! cp "$resolved" "$tmp" || ! chmod 755 "$tmp" || ! mv -n "$tmp" "$seed"; then
            rm -f "$tmp"
            bashio::log.error "Cannot seed Claude $version; check free space and permissions in /data"
            return 1
        fi
        rm -f "$tmp"
    fi

    # A pre-existing slot must be a real, runnable binary for this version.
    # Preserve invalid files for diagnosis rather than silently replacing them.
    if [ -L "$seed" ] || [ ! -f "$seed" ] || [ ! -x "$seed" ] \
        || ! version_output=$(timeout 15 "$seed" --version) \
        || [ "$version_output" != "$version (Claude Code)" ]; then
        bashio::log.error "Claude seed at $seed is not a runnable native version; leaving $launcher unchanged. Check this file before retrying"
        return 1
    fi
    if ! ln -sfn "$seed" "$launcher"; then
        bashio::log.error "Cannot create Claude launcher at $launcher; check permissions in /data"
        return 1
    fi
    bashio::log.info "Initialized native Claude launcher with persistent version $version"
}

# Initialize environment for Claude Code CLI using /data (HA best practice)
init_environment() {
    # Use /data exclusively - guaranteed writable by HA Supervisor
    local data_home="/data/home"
    local config_dir="/data/.config"
    local cache_dir="/data/.cache"
    local state_dir="/data/.local/state"

    bashio::log.info "Initializing Claude Code environment in /data..."

    # Create all required directories
    if ! mkdir -p "$data_home" "$config_dir" "$cache_dir" "$state_dir" "/data/.local"; then
        bashio::log.error "Failed to create directories in /data"
        exit 1
    fi

    # Set permissions
    chmod 755 "$data_home" "$config_dir" "$cache_dir" "$state_dir"

    # Set XDG and application environment variables
    export HOME="$data_home"
    export XDG_CONFIG_HOME="$config_dir"
    export XDG_CACHE_HOME="$cache_dir"
    export XDG_STATE_HOME="$state_dir"
    export XDG_DATA_HOME="/data/.local/share"

    # Keep normal interactive sessions in the classic renderer so the web
    # terminal retains browser scrolling and selection. This supported override
    # takes precedence over CLAUDE_CODE_NO_FLICKER and a saved tui=fullscreen
    # preference.
    export CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1
    bashio::log.info "Claude renderer: classic for normal interactive launches"

    # Ensure claude binary is in PATH (both for this script and spawned shells)
    # Add both /root/.local/bin (where it's installed) and $HOME/.local/bin (where Claude expects it)
    export PATH="$data_home/.local/bin:/root/.local/bin:${PATH}"
    if ! grep -q '/.local/bin' /root/.bashrc 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:/root/.local/bin:${PATH}"' >> /root/.bashrc
    fi

    bootstrap_claude_launcher

    # Configure Claude Code's built-in background auto-updater.
    # The native install keeps itself current in the background while running and
    # switches to the new version on the next launch, so there is no need to
    # reinstall on every startup. Honour the user's auto_update_claude option by
    # toggling DISABLE_AUTOUPDATER (the variable Claude's native updater respects).
    local auto_update_claude
    auto_update_claude=$(get_addon_option 'auto_update_claude' 'true' "${AUTO_UPDATE_CLAUDE:-}")
    if [ "$auto_update_claude" = "true" ]; then
        unset DISABLE_AUTOUPDATER
        bashio::log.info "Claude auto-update: enabled (native background updater)"
    else
        export DISABLE_AUTOUPDATER=1
        bashio::log.info "Claude auto-update: disabled (DISABLE_AUTOUPDATER=1)"
    fi

    bashio::log.info "Environment initialized:"
    bashio::log.info "  - Home: $HOME"
    bashio::log.info "  - Config: $XDG_CONFIG_HOME"
    bashio::log.info "  - Cache: $XDG_CACHE_HOME"
}

# Apply the configured default permission mode to Claude's user settings.
#
# Claude reads the per-session default from `permissions.defaultMode` in its
# user settings.json (under CLAUDE_CONFIG_DIR, or ~/.claude when unset). Writing
# it here means every launch path picks it up: auto-launch, the session picker,
# and any `claude` the user runs manually. Users can still cycle modes during a
# session with Shift+Tab — this only sets the starting default on each boot.
configure_permission_mode() {
    local mode
    mode=$(get_addon_option 'permission_mode' 'auto' "${PERMISSION_MODE:-}")

    local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    local settings_file="$config_dir/settings.json"

    bashio::log.info "Setting default permission mode: ${mode}"

    # Setting the default mode is a convenience, not critical to the terminal
    # working — so failures here only warn and continue (never abort startup).
    if ! mkdir -p "$config_dir"; then
        bashio::log.warning "Could not create ${config_dir}; leaving permission mode unset"
        return 0
    fi

    # Start from existing settings when valid, otherwise a fresh object, so we
    # never clobber other settings the user (or Claude) has written.
    if [ ! -s "$settings_file" ] || ! jq empty "$settings_file" 2>/dev/null; then
        echo '{}' > "$settings_file" 2>/dev/null || true
    fi

    # Merge permissions.defaultMode, preserving any other settings.
    local tmp
    if ! tmp="$(mktemp)"; then
        bashio::log.warning "Could not create a temp file; leaving permission mode unchanged"
        return 0
    fi
    if jq --arg mode "$mode" '.permissions.defaultMode = $mode' "$settings_file" > "$tmp" 2>/dev/null \
        && mv "$tmp" "$settings_file" 2>/dev/null; then
        chmod 644 "$settings_file" 2>/dev/null || true
    else
        rm -f "$tmp"
        bashio::log.warning "Could not update ${settings_file}; leaving permission mode unchanged"
    fi

    # 'auto' mode is gated behind an opt-in for non-first-party providers (Bedrock,
    # Vertex AI, Foundry) and is harmless to set for first-party Anthropic logins.
    # If the plan/model doesn't support it, Claude falls back to prompting rather
    # than failing to launch.
    if [ "$mode" = "auto" ]; then
        export CLAUDE_CODE_ENABLE_AUTO_MODE=1
        bashio::log.info "Auto mode opt-in enabled (CLAUDE_CODE_ENABLE_AUTO_MODE=1)"
    fi
}

# Verify required tools are available (installed at build time)
install_tools() {
    bashio::log.info "Verifying tools..."
    local tool
    for tool in ttyd tmux; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            bashio::log.error "${tool} not found - image may be corrupted"
            exit 1
        fi
    done
    bashio::log.info "Tools verified successfully"
}

# Install the add-on's Home Assistant context for Claude.
#
# The file goes in Claude's user-level rules directory, which Claude loads in
# every session. It lives in add-on private storage and belongs to the add-on,
# so it is replaced on every start. /config/CLAUDE.md and ~/.claude/CLAUDE.md
# are left to the user.
install_claude_context() {
    local source_file="/opt/home-assistant-context.md"
    local rules_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rules"
    local target_file="${rules_dir}/home-assistant.md"

    if mkdir -p "$rules_dir" && cp "$source_file" "$target_file"; then
        chmod 644 "$target_file" 2>/dev/null || true
    else
        bashio::log.warning "Could not install Home Assistant context to ${target_file}"
    fi

    remove_legacy_claude_context
}

# Earlier versions copied their context file to /config/CLAUDE.md. Remove that
# copy only if it is byte-identical to a version the add-on shipped, so it no
# longer loads alongside the new context. A modified copy belongs to the user.
remove_legacy_claude_context() {
    local legacy_file="/config/CLAUDE.md"
    local legacy_hash

    [ -f "$legacy_file" ] || return 0
    legacy_hash=$(sha256sum "$legacy_file" 2>/dev/null | cut -d ' ' -f1) || return 0

    case "$legacy_hash" in
        f506ca060ee1d35d20a12cce8f726e939acdb3906ab37345717dc2ba9065e62e | \
        0d34bb34ceac87c85b311f5ab05b99bb5265d0ede033f5f6c5bef59457449447 | \
        94f706d977f793d9544e0db9648940133e69c442c123849d601512017696e7e7 | \
        20d7d885a51d4c655e974fc87074503499db090ed7b09310130c36b9ba7d5ad7 | \
        5300121d13cbfe2f31acf2b6a5bc7450e6c5b10547ff52455baea233252ee21a | \
        2658f4bd9c7b177923bd2e71661353872e0beb1f9bd0f509b2c9332c27c23093 | \
        fd7b8656947d7702f6e6d858888975d1e16e393f0e1abe0e685b6461b77ce061 | \
        ae50b64a39798879e2dfb4bcf1879b64d7b5e979e87f1ac7db5f37baf23d30dc | \
        cd1100a200c0a4330a29453404676bc3ffc92b63a3fe4bf78539bc8450e0ff92 | \
        7c955377b3b5ffce7ba2492b75a0149770f2e1826c8811f4c53fc063615c25ca | \
        c171fabffe49e073d3137a443779972d94496ec2bcb8743f1d8cac67efbc1b33)
            if rm -f "$legacy_file"; then
                bashio::log.info "Removed unmodified /config/CLAUDE.md installed by an earlier add-on version"
            fi
            ;;
        *)
            bashio::log.info "Keeping /config/CLAUDE.md because it differs from the add-on's old copy; Claude loads it as project instructions"
            ;;
    esac
}

# Setup session picker script
setup_session_picker() {
    # Copy session picker script from built-in location
    if [ -f "/opt/scripts/claude-session-picker.sh" ]; then
        if ! cp /opt/scripts/claude-session-picker.sh /usr/local/bin/claude-session-picker; then
            bashio::log.error "Failed to copy claude-session-picker script"
            exit 1
        fi
        chmod +x /usr/local/bin/claude-session-picker
        bashio::log.info "Session picker script installed successfully"
    else
        bashio::log.warning "Session picker script not found, using auto-launch mode only"
    fi
}

# Determine Claude launch command based on configuration
get_claude_launch_command() {
    local auto_launch_claude
    auto_launch_claude=$(get_addon_option 'auto_launch_claude' 'true' "${AUTO_LAUNCH_CLAUDE:-}")

    # Note: updates are handled by Claude's native background auto-updater
    # (configured in init_environment), so we no longer reinstall on launch.
    # Re-running https://claude.ai/install.sh unconditionally re-downloaded the
    # full ~215MB binary on every terminal open, which made startup slow.
    if [ "$auto_launch_claude" = "true" ]; then
        # Auto-launch Claude directly
        echo "clear && claude"
    else
        # Show interactive session picker
        if [ -f /usr/local/bin/claude-session-picker ]; then
            echo "clear && /usr/local/bin/claude-session-picker"
        else
            # Fallback if session picker is missing
            bashio::log.warning "Session picker not found, falling back to auto-launch"
            echo "clear && claude"
        fi
    fi
}


# Start main web terminal
start_web_terminal() {
    local port=7681
    bashio::log.info "Starting web terminal on port ${port}..."
    
    # Log environment information for debugging
    bashio::log.info "Environment variables:"
    bashio::log.info "HOME=${HOME}"

    # Get the appropriate launch command based on configuration
    local launch_command
    launch_command=$(get_claude_launch_command)
    
    # Log the configuration being used
    local auto_launch_claude
    auto_launch_claude=$(get_addon_option 'auto_launch_claude' 'true' "${AUTO_LAUNCH_CLAUDE:-}")
    bashio::log.info "Auto-launch Claude: ${auto_launch_claude}"

    local ttyd_index="/opt/ttyd-index.html"
    local ttyd_index_args=()
    if [ -f "$ttyd_index" ]; then
        ttyd_index_args=(--index "$ttyd_index")
    else
        bashio::log.warning "Patched ttyd index not found; falling back to bundled terminal UI"
    fi
    
    # Each connection attaches to one shared tmux session, so a browser refresh
    # or ingress reconnect resumes the running session instead of killing it.
    exec ttyd \
        --port "${port}" \
        --interface 0.0.0.0 \
        "${ttyd_index_args[@]}" \
        --writable \
        /opt/scripts/attach-session.sh "$launch_command"
}

# Main execution
main() {
    bashio::log.info "Initializing Claude Code add-on..."

    init_environment
    configure_permission_mode
    install_tools
    install_claude_context
    setup_session_picker
    start_web_terminal
}

# Execute main function
main "$@"
