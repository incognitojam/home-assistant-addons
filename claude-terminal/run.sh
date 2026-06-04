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

# Initialize environment for Claude Code CLI using /data (HA best practice)
init_environment() {
    # Use /data exclusively - guaranteed writable by HA Supervisor
    local data_home="/data/home"
    local config_dir="/data/.config"
    local cache_dir="/data/.cache"
    local state_dir="/data/.local/state"
    local claude_config_dir="/data/.config/claude"

    bashio::log.info "Initializing Claude Code environment in /data..."

    # Create all required directories
    if ! mkdir -p "$data_home" "$config_dir/claude" "$cache_dir" "$state_dir" "/data/.local"; then
        bashio::log.error "Failed to create directories in /data"
        exit 1
    fi

    # Set permissions
    chmod 755 "$data_home" "$config_dir" "$cache_dir" "$state_dir" "$claude_config_dir"

    # Set XDG and application environment variables
    export HOME="$data_home"
    export XDG_CONFIG_HOME="$config_dir"
    export XDG_CACHE_HOME="$cache_dir"
    export XDG_STATE_HOME="$state_dir"
    export XDG_DATA_HOME="/data/.local/share"

    # Ensure claude binary is in PATH (both for this script and spawned shells)
    # Add both /root/.local/bin (where it's installed) and $HOME/.local/bin (where Claude expects it)
    export PATH="$data_home/.local/bin:/root/.local/bin:${PATH}"
    if ! grep -q '/.local/bin' /root/.bashrc 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:/root/.local/bin:${PATH}"' >> /root/.bashrc
    fi

    # Ensure Claude is available at $HOME/.local/bin
    # Only create symlink to build-time binary as fallback — don't overwrite
    # a version installed by the auto-updater (which persists in /data)
    mkdir -p "$data_home/.local/bin"
    if [ ! -e "$data_home/.local/bin/claude" ] && [ ! -L "$data_home/.local/bin/claude" ]; then
        ln -sf /root/.local/bin/claude "$data_home/.local/bin/claude" 2>/dev/null || true
        bashio::log.info "Created symlink to build-time Claude binary"
    else
        bashio::log.info "Using existing Claude binary at $data_home/.local/bin/claude"
    fi

    # Claude-specific environment variables
    export ANTHROPIC_CONFIG_DIR="$claude_config_dir"
    export ANTHROPIC_HOME="/data"

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

    # Migrate any existing authentication files from legacy locations
    migrate_legacy_auth_files "$claude_config_dir"

    bashio::log.info "Environment initialized:"
    bashio::log.info "  - Home: $HOME"
    bashio::log.info "  - Config: $XDG_CONFIG_HOME"
    bashio::log.info "  - Claude config: $ANTHROPIC_CONFIG_DIR"
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

# One-time migration of existing authentication files
migrate_legacy_auth_files() {
    local target_dir="$1"
    local migrated=false

    bashio::log.info "Checking for existing authentication files to migrate..."

    # Check common legacy locations
    local legacy_locations=(
        "/root/.config/anthropic"
        "/root/.anthropic" 
        "/config/claude-config"
        "/tmp/claude-config"
    )

    for legacy_path in "${legacy_locations[@]}"; do
        if [ -d "$legacy_path" ] && [ "$(ls -A "$legacy_path" 2>/dev/null)" ]; then
            bashio::log.info "Migrating auth files from: $legacy_path"
            
            # Copy files to new location
            if cp -r "$legacy_path"/* "$target_dir/" 2>/dev/null; then
                # Set proper permissions
                find "$target_dir" -type f -exec chmod 600 {} \;
                
                # Create compatibility symlink if this is a standard location
                if [[ "$legacy_path" == "/root/.config/anthropic" ]] || [[ "$legacy_path" == "/root/.anthropic" ]]; then
                    rm -rf "$legacy_path"
                    ln -sf "$target_dir" "$legacy_path"
                    bashio::log.info "Created compatibility symlink: $legacy_path -> $target_dir"
                fi
                
                migrated=true
                bashio::log.info "Migration completed from: $legacy_path"
            else
                bashio::log.warning "Failed to migrate from: $legacy_path"
            fi
        fi
    done

    if [ "$migrated" = false ]; then
        bashio::log.info "No existing authentication files found to migrate"
    fi
}

# Verify required tools are available (installed at build time)
install_tools() {
    bashio::log.info "Verifying tools..."
    if ! command -v ttyd >/dev/null 2>&1; then
        bashio::log.error "ttyd not found - image may be corrupted"
        exit 1
    fi
    bashio::log.info "Tools verified successfully"
}

# Install Claude context documentation to /config
install_claude_context() {
    local source_file="/opt/CLAUDE.md"
    local target_file="/config/CLAUDE.md"

    # Check if source file exists
    if [ -f "$source_file" ]; then
        # Install or update CLAUDE.md in /config
        if [ ! -f "$target_file" ]; then
            bashio::log.info "Installing CLAUDE.md to /config for Claude context..."
            if cp "$source_file" "$target_file"; then
                chmod 644 "$target_file"
                bashio::log.info "CLAUDE.md installed successfully"
            else
                bashio::log.warning "Failed to install CLAUDE.md, continuing anyway..."
            fi
        else
            # Update if source is newer
            if [ "$source_file" -nt "$target_file" ]; then
                bashio::log.info "Updating CLAUDE.md in /config..."
                if cp "$source_file" "$target_file"; then
                    chmod 644 "$target_file"
                    bashio::log.info "CLAUDE.md updated successfully"
                else
                    bashio::log.warning "Failed to update CLAUDE.md, continuing anyway..."
                fi
            fi
        fi
    else
        bashio::log.debug "No CLAUDE.md found in container, skipping installation"
    fi
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

    # Setup authentication helper if it exists
    if [ -f "/opt/scripts/claude-auth-helper.sh" ]; then
        chmod +x /opt/scripts/claude-auth-helper.sh
        bashio::log.info "Authentication helper script ready"
    fi
}

# Legacy monitoring functions removed - using simplified /data approach

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
    bashio::log.info "ANTHROPIC_CONFIG_DIR=${ANTHROPIC_CONFIG_DIR}"
    bashio::log.info "HOME=${HOME}"

    # Get the appropriate launch command based on configuration
    local launch_command
    launch_command=$(get_claude_launch_command)
    
    # Log the configuration being used
    local auto_launch_claude
    auto_launch_claude=$(get_addon_option 'auto_launch_claude' 'true' "${AUTO_LAUNCH_CLAUDE:-}")
    bashio::log.info "Auto-launch Claude: ${auto_launch_claude}"
    
    # Run ttyd with improved configuration
    exec ttyd \
        --port "${port}" \
        --interface 0.0.0.0 \
        --writable \
        bash -c "$launch_command"
}

# Run health check
run_health_check() {
    if [ -f "/opt/scripts/health-check.sh" ]; then
        bashio::log.info "Running system health check..."
        chmod +x /opt/scripts/health-check.sh
        /opt/scripts/health-check.sh || bashio::log.warning "Some health checks failed but continuing..."
    fi
}

# Main execution
main() {
    bashio::log.info "Initializing Claude Code add-on..."

    # Run diagnostics first (especially helpful for VirtualBox issues)
    run_health_check

    init_environment
    configure_permission_mode
    install_tools
    install_claude_context
    setup_session_picker
    start_web_terminal
}

# Execute main function
main "$@"