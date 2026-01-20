#!/usr/bin/with-contenv bashio

set -e
set -o pipefail

init_environment() {
    local data_home="/data/home"
    local cache_dir="/data/.cache"
    local state_dir="/data/.local/state"
    local data_dir="/data/.local"
    local config_dir="/config/opencode"

    bashio::log.info "Initializing OpenCode environment..."

    if ! mkdir -p "$data_home" "$cache_dir" "$state_dir" "$data_dir" "$config_dir" "$data_home/.opencode/bin"; then
        bashio::log.error "Failed to create required directories"
        exit 1
    fi

    chmod 755 "$data_home" "$cache_dir" "$state_dir" "$data_dir" "$config_dir"

    export HOME="$data_home"
    export XDG_CACHE_HOME="$cache_dir"
    export XDG_STATE_HOME="$state_dir"
    export XDG_DATA_HOME="/data/.local/share"
    export XDG_CONFIG_HOME="/data/.config"
    export OPENCODE_CONFIG_DIR="$config_dir"
    export PATH="$data_home/.opencode/bin:/root/.opencode/bin:${PATH}"

    ln -sf /root/.opencode/bin/opencode "$data_home/.opencode/bin/opencode" 2>/dev/null || true
}

install_agent_context() {
    local source_file="/opt/AGENTS.md"
    local target_file="/config/AGENTS.md"

    if [ -f "$source_file" ]; then
        if [ ! -f "$target_file" ]; then
            bashio::log.info "Installing AGENTS.md to /config..."
            if cp "$source_file" "$target_file"; then
                chmod 644 "$target_file"
                bashio::log.info "AGENTS.md installed successfully"
            else
                bashio::log.warning "Failed to install AGENTS.md"
            fi
        else
            if [ "$source_file" -nt "$target_file" ]; then
                bashio::log.info "Updating AGENTS.md in /config..."
                if cp "$source_file" "$target_file"; then
                    chmod 644 "$target_file"
                    bashio::log.info "AGENTS.md updated successfully"
                else
                    bashio::log.warning "Failed to update AGENTS.md"
                fi
            fi
        fi
    fi
}

start_web_ui() {
    local port
    local hostname
    local username
    local password
    local base_path

    if [ -n "${SUPERVISOR_TOKEN:-}" ]; then
        port=$(bashio::config 'server_port' '4096')
        hostname=$(bashio::config 'server_hostname' '0.0.0.0')
        username=$(bashio::config 'server_username')
        password=$(bashio::config 'server_password')
        base_path=$(bashio::config 'server_base_path')
    else
        port="${OPENCODE_SERVER_PORT:-4096}"
        hostname="${OPENCODE_SERVER_HOSTNAME:-0.0.0.0}"
        username="${OPENCODE_SERVER_USERNAME:-}"
        password="${OPENCODE_SERVER_PASSWORD:-}"
        base_path="${OPENCODE_SERVER_BASE_PATH:-}"
    fi

    if [ -n "$username" ]; then
        export OPENCODE_SERVER_USERNAME="$username"
    fi

    if [ -n "$password" ]; then
        export OPENCODE_SERVER_PASSWORD="$password"
    else
        bashio::log.warning "OPENCODE_SERVER_PASSWORD not set; web UI will be unsecured."
    fi

    local args
    args=(web --hostname "$hostname" --port "$port")
    if [ -n "$base_path" ]; then
        args+=(--base-path "$base_path")
    fi

    bashio::log.info "Starting OpenCode web UI on ${hostname}:${port}..."
    exec opencode "${args[@]}"
}

main() {
    init_environment
    install_agent_context
    start_web_ui
}

main "$@"
