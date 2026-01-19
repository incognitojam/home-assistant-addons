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

start_web_ui() {
    local port
    local hostname
    local username
    local password

    if [ -n "${SUPERVISOR_TOKEN:-}" ]; then
        port=$(bashio::config 'server_port' '4096')
        hostname=$(bashio::config 'server_hostname' '0.0.0.0')
        username=$(bashio::config 'server_username')
        password=$(bashio::config 'server_password')
    else
        port="${OPENCODE_SERVER_PORT:-4096}"
        hostname="${OPENCODE_SERVER_HOSTNAME:-0.0.0.0}"
        username="${OPENCODE_SERVER_USERNAME:-}"
        password="${OPENCODE_SERVER_PASSWORD:-}"
    fi

    if [ -n "$username" ]; then
        export OPENCODE_SERVER_USERNAME="$username"
    fi

    if [ -n "$password" ]; then
        export OPENCODE_SERVER_PASSWORD="$password"
    else
        bashio::log.warning "OPENCODE_SERVER_PASSWORD not set; web UI will be unsecured."
    fi

    bashio::log.info "Starting OpenCode web UI on ${hostname}:${port}..."
    exec opencode web --hostname "$hostname" --port "$port"
}

main() {
    init_environment
    start_web_ui
}

main "$@"
