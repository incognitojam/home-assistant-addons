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
    local npm_prefix="/data/npm"

    bashio::log.info "Initializing Codex environment in /data..."

    if ! mkdir -p \
        "${data_home}" \
        "${codex_home}" \
        "${xdg_config_home}" \
        "${xdg_cache_home}" \
        "${xdg_state_home}" \
        "${xdg_data_home}" \
        "${npm_prefix}/bin" \
        "${data_home}/.local/bin"; then
        bashio::log.error "Failed to create persistent directories in /data"
        exit 1
    fi

    chmod 700 "${codex_home}"
    chmod 755 \
        "${data_home}" \
        "${xdg_config_home}" \
        "${xdg_cache_home}" \
        "${xdg_state_home}" \
        "${xdg_data_home}" \
        "${npm_prefix}" \
        "${npm_prefix}/bin"

    export HOME="${data_home}"
    export CODEX_HOME="${codex_home}"
    export CODEX_SQLITE_HOME="${codex_home}"
    export XDG_CONFIG_HOME="${xdg_config_home}"
    export XDG_CACHE_HOME="${xdg_cache_home}"
    export XDG_STATE_HOME="${xdg_state_home}"
    export XDG_DATA_HOME="${xdg_data_home}"
    export NPM_CONFIG_PREFIX="${npm_prefix}"

    write_shell_profile

    bashio::log.info "Codex state: ${CODEX_HOME}"
    bashio::log.info "Persistent npm prefix: ${NPM_CONFIG_PREFIX}"
    bashio::log.info "Working directory: /config"
}

write_shell_profile() {
    local profile="${HOME}/.bashrc"

    if [ -f "${profile}" ] && grep -q 'NPM_CONFIG_PREFIX="/data/npm"' "${profile}"; then
        return 0
    fi

    if [ -f "${profile}" ] && grep -q "Codex for Home Assistant" "${profile}"; then
        cat >> "${profile}" <<'EOF'

# Codex persistent npm prefix
export NPM_CONFIG_PREFIX="/data/npm"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
EOF
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
export NPM_CONFIG_PREFIX="/data/npm"
export PATH="$NPM_CONFIG_PREFIX/bin:$HOME/.local/bin:/usr/local/bin:$PATH"
cd /config 2>/dev/null || true
EOF
}

# Codex loads AGENTS.md from CODEX_HOME as global instructions. Keep user
# overrides and edits; the private stamp tracks only copies managed here.
install_codex_context() {
    local source_file="/opt/home-assistant-context.md"
    local target_file="${CODEX_HOME}/AGENTS.md"
    local stamp_file="${CODEX_HOME}/home-assistant-context.sha256"
    local source_hash target_hash previous_hash=""

    remove_legacy_codex_context

    if ! source_hash=$(sha256sum "$source_file" 2>/dev/null | cut -d ' ' -f1); then
        bashio::log.warning "Could not checksum bundled Home Assistant context"
        return 0
    fi

    if [ -f "$stamp_file" ]; then
        previous_hash=$(head -n 1 "$stamp_file" 2>/dev/null || true)
    fi

    if [ -e "$target_file" ] || [ -L "$target_file" ]; then
        target_hash=$(sha256sum "$target_file" 2>/dev/null | cut -d ' ' -f1) || target_hash=""
        if [ -L "$target_file" ] || [ ! -f "$target_file" ] || {
            [ "$target_hash" != "$source_hash" ] && {
                [ -z "$previous_hash" ] || [ "$target_hash" != "$previous_hash" ];
            };
        }; then
            bashio::log.info "Keeping ${target_file} because it contains user instructions"
            return 0
        fi
    fi

    if cp "$source_file" "$target_file"; then
        chmod 644 "$target_file" 2>/dev/null || true
        if ! printf '%s\n' "$source_hash" > "$stamp_file"; then
            bashio::log.warning "Could not save Home Assistant context checksum; future updates will preserve this copy"
        fi
    else
        bashio::log.warning "Could not install Home Assistant context to ${target_file}"
    fi
}

# Match all historical shipped copies, or the last installed legacy checksum.
# Never follow a /config symlink; it belongs to the user even if bytes match.
remove_legacy_codex_context() {
    local legacy_file="/config/AGENTS.md"
    local stamp_file="${CODEX_HOME}/AGENTS.md.sha256"
    local legacy_hash previous_hash=""
    local shipped=false

    if [ -f "$legacy_file" ] && [ ! -L "$legacy_file" ]; then
        legacy_hash=$(sha256sum "$legacy_file" 2>/dev/null | cut -d ' ' -f1) || return 0
        if [ -f "$stamp_file" ]; then
            previous_hash=$(head -n 1 "$stamp_file" 2>/dev/null || true)
        fi
        case "$legacy_hash" in
            66b1475f9d78c8cb4b950e1dd7c61e8667de5f0de008f140f2421d917d24b482 | \
            6c44efa8f67c9d46cef1b949a4eabbcc4d56565261bba8d5424bc58854b8b0bc | \
            5237c07aef93d4cbcbe2b976bc73ca47106cba6a975e4cab4c2ed19f82b9035b | \
            c88e5a49ce4db534d1b8bd4e0707e0a2717371f200113b47be2caaf4b1a328f8)
                shipped=true ;;
        esac
        if [ "$shipped" = true ] || { [ -n "$previous_hash" ] && [ "$legacy_hash" = "$previous_hash" ]; }; then
            if rm -f "$legacy_file"; then
                bashio::log.info "Removed unmodified /config/AGENTS.md installed by an earlier add-on version"
            else
                bashio::log.warning "Could not remove legacy /config/AGENTS.md"
                return 0
            fi
        else
            bashio::log.info "Keeping /config/AGENTS.md because it differs from the add-on's old copy"
        fi
    elif [ -e "$legacy_file" ] || [ -L "$legacy_file" ]; then
        bashio::log.info "Keeping /config/AGENTS.md because it is not a regular add-on context file"
    fi
    rm -f "$stamp_file" || bashio::log.warning "Could not retire legacy context checksum"
}

verify_tools() {
    local missing=false
    local tool

    for tool in codex-auth-launcher ttyd ha git jq node npm reset-codex-version rg; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            bashio::log.error "Required tool not found: ${tool}"
            missing=true
        fi
    done

    if [ "${missing}" = true ]; then
        exit 1
    fi

    select_codex

    if ha help >/dev/null 2>&1; then
        bashio::log.info "Home Assistant CLI: available"
    else
        bashio::log.warning "Home Assistant CLI is installed but did not pass its help check"
    fi
}

select_codex() {
    local bundled_codex="/usr/local/bin/codex"
    local persistent_codex="${NPM_CONFIG_PREFIX}/bin/codex"
    local selected_codex=""
    local selected_version=""

    if [ -e "${persistent_codex}" ] || [ -L "${persistent_codex}" ]; then
        if [ -x "${persistent_codex}" ] \
            && selected_version="$("${persistent_codex}" --version 2>/dev/null)" \
            && [ -n "${selected_version}" ]; then
            selected_codex="${persistent_codex}"
        else
            bashio::log.warning "Persistent Codex failed its startup check; using the bundled fallback"
            bashio::log.warning "Run !/usr/local/bin/reset-codex-version from Codex to remove the broken override"
        fi
    fi

    if [ -z "${selected_codex}" ]; then
        if [ ! -x "${bundled_codex}" ] \
            || ! selected_version="$("${bundled_codex}" --version 2>/dev/null)" \
            || [ -z "${selected_version}" ]; then
            bashio::log.error "Bundled Codex failed its startup check"
            exit 1
        fi
        selected_codex="${bundled_codex}"
    fi

    export CODEX_EXECUTABLE="${selected_codex}"
    bashio::log.info "Codex command: ${CODEX_EXECUTABLE}"
    bashio::log.info "Codex version: ${selected_version}"
}

start_web_terminal() {
    bashio::log.info "Starting Codex terminal on port ${PORT}..."

    cd /config

    exec /usr/bin/ttyd \
        --port "${PORT}" \
        --interface 0.0.0.0 \
        --writable \
        /bin/bash -lc "cd /config && exec /usr/local/bin/codex-auth-launcher"
}

main() {
    bashio::log.info "Starting Codex for Home Assistant..."

    init_environment
    install_codex_context
    verify_tools
    start_web_terminal
}

main "$@"
