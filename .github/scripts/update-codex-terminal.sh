#!/usr/bin/env bash
# Pins codex-terminal to a newer Codex CLI and bumps the add-on patch version.
# Uses CODEX_RELEASE_OVERRIDE if set, otherwise npm's latest @openai/codex.
set -euo pipefail

addon_dir="${ADDON_DIR:-codex-terminal}"
dockerfile="${addon_dir}/Dockerfile"
config="${addon_dir}/config.yaml"
changelog="${addon_dir}/CHANGELOG.md"

write_output() {
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT}"
    fi
}

validate_version() {
    if [[ ! "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf 'Invalid %s version: %s\n' "$1" "$2" >&2
        exit 1
    fi
}

version_gt() {
    awk -v a="$1" -v b="$2" '
        BEGIN {
            split(a, av, "."); split(b, bv, ".")
            for (i = 1; i <= 3; i++) {
                if (av[i] + 0 > bv[i] + 0) exit 0
                if (av[i] + 0 < bv[i] + 0) exit 1
            }
            exit 1
        }
    '
}

codex_release="${CODEX_RELEASE_OVERRIDE:-}"
if [[ -z "${codex_release}" ]]; then
    # The Dockerfile installs from npm, so npm's latest tag is the source of truth.
    codex_release="$(curl -fsSL https://registry.npmjs.org/@openai/codex | jq -r '."dist-tags".latest')"
fi
codex_release="${codex_release#rust-v}"
codex_release="${codex_release#v}"
validate_version "Codex release" "${codex_release}"

current_codex_release="$(awk -F= '/^ARG CODEX_RELEASE=/ { print $2; exit }' "${dockerfile}")"
current_build_version="$(awk -F= '/^ARG BUILD_VERSION=/ { print $2; exit }' "${dockerfile}")"
current_addon_version="$(awk -F': *' '/^version:/ { gsub(/"/, "", $2); print $2; exit }' "${config}")"
validate_version "current Codex release" "${current_codex_release}"
validate_version "Docker build" "${current_build_version}"
validate_version "add-on" "${current_addon_version}"

if [[ "${current_addon_version}" != "${current_build_version}" ]]; then
    printf 'config.yaml version (%s) does not match Dockerfile BUILD_VERSION (%s)\n' \
        "${current_addon_version}" "${current_build_version}" >&2
    exit 1
fi

if ! version_gt "${codex_release}" "${current_codex_release}"; then
    write_output changed false
    printf 'Codex %s is not newer than the pinned %s\n' "${codex_release}" "${current_codex_release}"
    exit 0
fi

addon_version="$(awk -v v="${current_addon_version}" 'BEGIN { split(v, p, "."); printf "%d.%d.%d\n", p[1], p[2], p[3] + 1 }')"

perl -pi -e "s/^ARG BUILD_VERSION=.*/ARG BUILD_VERSION=${addon_version}/" "${dockerfile}"
perl -pi -e "s/^ARG CODEX_RELEASE=.*/ARG CODEX_RELEASE=${codex_release}/" "${dockerfile}"
perl -pi -e "s/^version: .*/version: \"${addon_version}\"/" "${config}"

ENTRY="## ${addon_version}

### Maintenance
- Update the pinned Codex CLI fallback to ${codex_release}.

" perl -0pi -e 's/\A(# Changelog\n\n)/$1$ENV{ENTRY}/' "${changelog}"

write_output changed true
write_output codex_release "${codex_release}"
write_output previous_codex_release "${current_codex_release}"
write_output addon_version "${addon_version}"
write_output previous_addon_version "${current_addon_version}"
printf 'Updated Codex %s -> %s, add-on %s -> %s\n' \
    "${current_codex_release}" "${codex_release}" "${current_addon_version}" "${addon_version}"
