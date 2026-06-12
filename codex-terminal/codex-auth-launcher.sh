#!/usr/bin/env bash

set -euo pipefail

launch_codex() {
    exec codex "$@"
}

is_logged_in() {
    codex login status >/dev/null 2>&1
}

show_auth_menu() {
    cat <<'EOF'

Welcome to Codex for Home Assistant

Codex needs authentication before it can start. Choose a login method:

  1. Sign in with Device Code
     Sign in from another device with a one-time code

  2. Provide your own API key
     Pay for what you use

EOF
}

login_with_device_code() {
    codex login --device-auth
}

login_with_api_key() {
    local api_key

    while true; do
        if ! IFS= read -r -s -p "OpenAI API key: " api_key; then
            printf '\n'
            return 1
        fi
        printf '\n'

        if [ -n "${api_key}" ]; then
            break
        fi

        printf 'API key cannot be empty.\n'
    done

    if printf '%s\n' "${api_key}" | codex login --with-api-key; then
        unset api_key
        return 0
    fi

    unset api_key
    return 1
}

run_auth_flow() {
    local choice

    while true; do
        show_auth_menu
        IFS= read -r -p "Select an auth method [1-2]: " choice || return 1

        case "${choice}" in
            1)
                if login_with_device_code; then
                    return 0
                fi
                ;;
            2)
                if login_with_api_key; then
                    return 0
                fi
                ;;
            *)
                printf 'Please enter 1 or 2.\n'
                continue
                ;;
        esac

        printf '\nAuthentication did not complete. Please try again.\n'
    done
}

main() {
    if is_logged_in; then
        launch_codex "$@"
    fi

    if run_auth_flow && is_logged_in; then
        launch_codex "$@"
    fi

    printf '\nCodex authentication is still incomplete. Restart the app to try again.\n' >&2
    return 1
}

main "$@"
