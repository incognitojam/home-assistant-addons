#!/usr/bin/env bash
set -euo pipefail

addon_dir="${ADDON_DIR:-codex-terminal}"
dockerfile="${addon_dir}/Dockerfile"
config="${addon_dir}/config.yaml"
changelog="${addon_dir}/CHANGELOG.md"

write_output() {
  local name="$1"
  local value="$2"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "${name}" "${value}" >> "${GITHUB_OUTPUT}"
  fi
}

normalize_codex_release() {
  local release="$1"

  release="${release#rust-v}"
  release="${release#v}"
  printf '%s\n' "${release}"
}

validate_version() {
  local name="$1"
  local version="$2"

  if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Invalid %s version: %s\n' "${name}" "${version}" >&2
    exit 1
  fi
}

version_gt() {
  awk -v a="$1" -v b="$2" '
    BEGIN {
      split(a, av, ".")
      split(b, bv, ".")
      for (i = 1; i <= 3; i++) {
        av[i] += 0
        bv[i] += 0
        if (av[i] > bv[i]) exit 0
        if (av[i] < bv[i]) exit 1
      }
      exit 1
    }
  '
}

bump_patch() {
  awk -v version="$1" '
    BEGIN {
      split(version, parts, ".")
      printf "%d.%d.%d\n", parts[1], parts[2], parts[3] + 1
    }
  '
}

latest_codex_release="${CODEX_RELEASE_OVERRIDE:-}"
if [[ -z "${latest_codex_release}" ]]; then
  curl_args=(-fsSL -H "Accept: application/vnd.github+json")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  latest_codex_release="$(
    curl "${curl_args[@]}" https://api.github.com/repos/openai/codex/releases/latest \
      | jq -r '.tag_name'
  )"
fi
latest_codex_release="$(normalize_codex_release "${latest_codex_release}")"
validate_version "Codex release" "${latest_codex_release}"

current_codex_release="$(awk -F= '/^ARG CODEX_RELEASE=/ { print $2; exit }' "${dockerfile}")"
current_addon_version="$(awk -F': *' '/^version:/ { gsub(/"/, "", $2); print $2; exit }' "${config}")"
current_build_version="$(awk -F= '/^ARG BUILD_VERSION=/ { print $2; exit }' "${dockerfile}")"

validate_version "current Codex release" "${current_codex_release}"
validate_version "add-on" "${current_addon_version}"
validate_version "Docker build" "${current_build_version}"

if [[ "${current_addon_version}" != "${current_build_version}" ]]; then
  printf 'config.yaml version (%s) does not match Dockerfile BUILD_VERSION (%s)\n' \
    "${current_addon_version}" \
    "${current_build_version}" >&2
  exit 1
fi

write_output "previous_codex_release" "${current_codex_release}"
write_output "codex_release" "${latest_codex_release}"
write_output "previous_addon_version" "${current_addon_version}"

if [[ "${latest_codex_release}" == "${current_codex_release}" ]]; then
  write_output "changed" "false"
  write_output "addon_version" "${current_addon_version}"
  printf 'Codex release is already current: %s\n' "${current_codex_release}"
  exit 0
fi

if ! version_gt "${latest_codex_release}" "${current_codex_release}"; then
  write_output "changed" "false"
  write_output "addon_version" "${current_addon_version}"
  printf 'Latest Codex release %s is not newer than current %s\n' \
    "${latest_codex_release}" \
    "${current_codex_release}"
  exit 0
fi

next_addon_version="$(bump_patch "${current_addon_version}")"
validate_version "next add-on" "${next_addon_version}"

perl -0pi -e "s/^ARG BUILD_VERSION=\\Q${current_addon_version}\\E$/ARG BUILD_VERSION=${next_addon_version}/m" "${dockerfile}"
perl -0pi -e "s/^ARG CODEX_RELEASE=\\Q${current_codex_release}\\E$/ARG CODEX_RELEASE=${latest_codex_release}/m" "${dockerfile}"
perl -0pi -e "s/^version: \"\\Q${current_addon_version}\\E\"$/version: \"${next_addon_version}\"/m" "${config}"

changelog_entry="## ${next_addon_version}

### Maintenance
- Update the pinned Codex standalone release to CLI ${latest_codex_release}.

"
ENTRY="${changelog_entry}" perl -0pi -e 's/\A(# Changelog\n\n)/$1$ENV{ENTRY}/' "${changelog}"

write_output "changed" "true"
write_output "addon_version" "${next_addon_version}"

printf 'Updated Codex from %s to %s and add-on from %s to %s\n' \
  "${current_codex_release}" \
  "${latest_codex_release}" \
  "${current_addon_version}" \
  "${next_addon_version}"
