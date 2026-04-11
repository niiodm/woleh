#!/usr/bin/env bash
# Open an SSH session on the staging host, starting in the staging deploy directory.
# Uses WOLEH_STAGING_SSH (default: woleh-staging) and WOLEH_STAGING_REMOTE_DIR like deploy.sh.
#
# Usage:
#   ./connect-staging.sh                 # interactive login shell in staging dir
#   ./connect-staging.sh docker compose ps
#   ./connect-staging.sh bash -lc 'df -h /'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/staging-util.sh"

host="$(staging_ssh_host)"
remote="$(staging_remote_dir_abs "$host")" || {
	echo "Could not resolve staging directory on ${host}. Check SSH and WOLEH_STAGING_REMOTE_DIR." >&2
	exit 1
}
rcd=$(printf '%q' "$remote")

if [[ $# -eq 0 ]]; then
	exec ssh -t "$host" "cd ${rcd} && exec bash -l"
else
	exec ssh -t "$host" "cd ${rcd} && $(printf '%q ' "$@")"
fi
