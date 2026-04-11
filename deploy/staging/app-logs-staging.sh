#!/usr/bin/env bash
# Stream logs for the staging API container only (Compose service: api).
# Uses WOLEH_STAGING_SSH and WOLEH_STAGING_REMOTE_DIR like deploy.sh.
#
# Usage:
#   ./app-logs-staging.sh # follow API logs (-f)
#   ./app-logs-staging.sh --tail=200
#   ./app-logs-staging.sh -f --since=10m
#
# Forwards arguments to: docker compose logs … api (adds -f only when you pass no arguments).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/staging-util.sh"

host="$(staging_ssh_host)"
remote="$(staging_remote_dir_abs "$host")" || {
	echo "Could not resolve staging directory on ${host}." >&2
	exit 1
}
rcd=$(printf '%q' "$remote")

if [[ $# -eq 0 ]]; then
	set -- -f
fi

exec ssh -t "$host" "cd ${rcd} && if docker info >/dev/null 2>&1; then exec docker compose logs $(printf '%q ' "$@") api; else exec sudo docker compose logs $(printf '%q ' "$@") api; fi"
