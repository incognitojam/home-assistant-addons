#!/usr/bin/env bash
# Print "present" if a GHCR image tag exists and "missing" if it does not.
# Exits non-zero, printing nothing, when the registry gives any other answer,
# so a registry outage can never be mistaken for an unpublished version.
#
# Usage: ghcr-tag-state.sh <owner/name> <tag>
# Set GHCR_TOKEN (e.g. the workflow's GITHUB_TOKEN) to see private packages.
set -euo pipefail

repository="$1"
tag="$2"

auth=()
if [[ -n "${GHCR_TOKEN:-}" ]]; then
    auth=(--user "token:${GHCR_TOKEN}")
fi

body="$(mktemp)"
trap 'rm -f "${body}"' EXIT

status="$(curl --silent --show-error --retry 3 --output "${body}" --write-out '%{http_code}' \
    "${auth[@]}" "https://ghcr.io/token?service=ghcr.io&scope=repository:${repository}:pull")"
case "${status}" in
    200) ;;
    # GHCR refuses a pull token for a package that does not exist, and also
    # for a private one the caller cannot read. Pushing still needs write
    # access, so a hidden package cannot be overwritten through this answer.
    401 | 403)
        echo "No pull access to ghcr.io/${repository} (HTTP ${status}); treating it as missing" >&2
        echo missing
        exit 0
        ;;
    *)
        echo "Unexpected HTTP ${status} from the GHCR token endpoint" >&2
        exit 1
        ;;
esac
token="$(jq -r .token "${body}")"

status="$(curl --silent --show-error --retry 3 --head --output /dev/null --write-out '%{http_code}' \
    --header "Authorization: Bearer ${token}" \
    --header "Accept: application/vnd.oci.image.index.v1+json" \
    --header "Accept: application/vnd.oci.image.manifest.v1+json" \
    --header "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
    --header "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "https://ghcr.io/v2/${repository}/manifests/${tag}")"
case "${status}" in
    200) echo present ;;
    404) echo missing ;;
    *)
        echo "Unexpected HTTP ${status} looking up ghcr.io/${repository}:${tag}" >&2
        exit 1
        ;;
esac
