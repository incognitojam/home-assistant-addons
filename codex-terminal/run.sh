#!/usr/bin/with-contenv bashio

set -e
set -o pipefail

readonly PORT=7681

init_environment() {
    local data_home="/data/home"
    local codex_home="/data/.codex"
    local xdg_config_home="/data/.config"
    local xdg_cache_home="/data/.cache"
    local xdg_state_home="/data/.local/state"
    local xdg_data_home="/data/.local/share"

    bashio::log.info "Initializing Codex environment in /data..."

    if ! mkdir -p \
        "${data_home}" \
        "${codex_home}" \
        "${xdg_config_home}" \
        "${xdg_cache_home}" \
        "${xdg_state_home}" \
        "${xdg_data_home}" \
        "${data_home}/.local/bin"; then
        bashio::log.error "Failed to create persistent directories in /data"
        exit 1
    fi

    chmod 700 "${codex_home}"
    chmod 755 "${data_home}" "${xdg_config_home}" "${xdg_cache_home}" "${xdg_state_home}" "${xdg_data_home}"

    export HOME="${data_home}"
    export CODEX_HOME="${codex_home}"
    export CODEX_SQLITE_HOME="${codex_home}"
    export XDG_CONFIG_HOME="${xdg_config_home}"
    export XDG_CACHE_HOME="${xdg_cache_home}"
    export XDG_STATE_HOME="${xdg_state_home}"
    export XDG_DATA_HOME="${xdg_data_home}"
    export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

    write_shell_profile

    bashio::log.info "Codex state: ${CODEX_HOME}"
    bashio::log.info "Working directory: /config"
}

write_shell_profile() {
    local profile="${HOME}/.bashrc"

    if [ -f "${profile}" ] && grep -q "Codex for Home Assistant" "${profile}"; then
        return 0
    fi

    cat >> "${profile}" <<'EOF'

# Codex for Home Assistant
export HOME="/data/home"
export CODEX_HOME="/data/.codex"
export CODEX_SQLITE_HOME="/data/.codex"
export XDG_CONFIG_HOME="/data/.config"
export XDG_CACHE_HOME="/data/.cache"
export XDG_STATE_HOME="/data/.local/state"
export XDG_DATA_HOME="/data/.local/share"
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
cd /config 2>/dev/null || true
EOF
}

install_codex_context() {
    local source_file="/opt/AGENTS.md"
    local target_file="/config/AGENTS.md"
    local stamp_file="${CODEX_HOME:-/data/.codex}/AGENTS.md.sha256"
    local source_hash=""
    local target_hash=""
    local previous_hash=""

    if [ ! -f "${source_file}" ]; then
        bashio::log.debug "No bundled AGENTS.md found, skipping installation"
        return 0
    fi

    if ! source_hash="$(sha256sum "${source_file}" 2>/dev/null | cut -d ' ' -f1)" || [ -z "${source_hash}" ]; then
        bashio::log.warning "Could not checksum bundled AGENTS.md, continuing without installing it"
        return 0
    fi

    mkdir -p "$(dirname "${stamp_file}")" 2>/dev/null || true

    if [ ! -f "${target_file}" ]; then
        bashio::log.info "Installing AGENTS.md to /config for Codex context..."
        if cp "${source_file}" "${target_file}"; then
            chmod 644 "${target_file}" 2>/dev/null || true
            printf '%s\n' "${source_hash}" > "${stamp_file}" 2>/dev/null || true
            bashio::log.info "AGENTS.md installed successfully"
        else
            bashio::log.warning "Failed to install AGENTS.md, continuing anyway"
        fi
        return 0
    fi

    if target_hash="$(sha256sum "${target_file}" 2>/dev/null | cut -d ' ' -f1)" && [ "${target_hash}" = "${source_hash}" ]; then
        printf '%s\n' "${source_hash}" > "${stamp_file}" 2>/dev/null || true
        return 0
    fi

    if [ -f "${stamp_file}" ]; then
        previous_hash="$(head -n 1 "${stamp_file}" 2>/dev/null || true)"
    fi

    if [ -n "${previous_hash}" ] && [ "${target_hash}" = "${previous_hash}" ]; then
        bashio::log.info "Updating AGENTS.md in /config..."
        if cp "${source_file}" "${target_file}"; then
            chmod 644 "${target_file}" 2>/dev/null || true
            printf '%s\n' "${source_hash}" > "${stamp_file}" 2>/dev/null || true
            bashio::log.info "AGENTS.md updated successfully"
        else
            bashio::log.warning "Failed to update AGENTS.md, continuing anyway"
        fi
    else
        bashio::log.info "Existing /config/AGENTS.md has local changes; leaving it unchanged"
    fi
}

verify_tools() {
    local missing=false
    local tool

    for tool in codex codex-auth-launcher ttyd ha git jq rg; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            bashio::log.error "Required tool not found: ${tool}"
            missing=true
        fi
    done

    if [ "${missing}" = true ]; then
        exit 1
    fi

    bashio::log.info "Codex version: $(codex --version 2>/dev/null || echo unknown)"
    if ha help >/dev/null 2>&1; then
        bashio::log.info "Home Assistant CLI: available"
    else
        bashio::log.warning "Home Assistant CLI is installed but did not pass its help check"
    fi
}

start_web_terminal() {
    bashio::log.info "Starting Codex terminal on port ${PORT}..."

    cd /config

    exec ttyd \
        --port "${PORT}" \
        --interface 0.0.0.0 \
        --writable \
        bash -lc "cd /config && exec codex-auth-launcher"
}

main() {
    bashio::log.info "Starting Codex for Home Assistant..."

    init_environment
    install_codex_context
    verify_tools
    start_web_terminal
}

main "$@"
