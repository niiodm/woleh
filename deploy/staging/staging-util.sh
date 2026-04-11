#!/usr/bin/env bash
# Shared helpers for laptop-side staging scripts (source this file; do not run directly).
# Matches deploy.sh: WOLEH_STAGING_SSH, WOLEH_STAGING_REMOTE_DIR.

staging_ssh_host() {
	printf '%s' "${WOLEH_STAGING_SSH:-woleh-staging}" | tr -d '\r\n'
}

# Print absolute remote staging directory (creates default path if missing, same as deploy.sh).
staging_remote_dir_abs() {
	local host="$1"
	host="${host//$'\r'/}"
	local out
	if [[ -n "${WOLEH_STAGING_REMOTE_DIR:-}" ]]; then
		local d="${WOLEH_STAGING_REMOTE_DIR//$'\r'/}"
		out="$(ssh -q "$host" "set -e; mkdir -p $(printf '%q' "$d"); cd $(printf '%q' "$d") && pwd")" || return 1
	else
		out="$(ssh -q "$host" "set -e; mkdir -p \"\$HOME/woleh/deploy/staging\"; cd \"\$HOME/woleh/deploy/staging\" && pwd")" || return 1
	fi
	out="${out//$'\r'/}"
	out="${out//$'\n'/}"
	out="${out//$'\t'/}"
	printf '%s' "$out"
}
