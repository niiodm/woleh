#!/usr/bin/env bash
# Deploy the staging stack (Postgres, API, Caddy).
#
# From your laptop (default): build bootJar locally, rsync + scp deploy/staging artifacts to the server
# (no git clone on the server), then SSH and run ./deploy.sh --local there.
# On the VPS: ./deploy.sh --local (expects this directory to already contain the bundle + .env).
#
# Laptop env: WOLEH_STAGING_SSH (default: woleh-staging), WOLEH_STAGING_REMOTE_DIR
# (optional; default remote dir is ~/woleh/deploy/staging — created if missing).
#
# Usage: ./deploy.sh [--local] [--skip-jar-sync] [--pull]
#
# --local — Run Docker Compose on this machine (use on the server).
# --skip-jar-sync — Do not rebuild the JAR or rsync it; reuse application.jar on the server (still rsyncs compose/Caddyfile/etc.).
# --pull — git pull --ff-only on your laptop before building (if REPO_ROOT is a git clone); on the
#          server, git pull only runs if a .git directory exists there.
#
# Server: Docker + Compose v2. On Amazon Linux 2023, --local can install Docker via dnf and the Compose CLI plugin.
# Laptop: keep deploy/staging/.env (from .env.example) to rsync, or create .env on the server once.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RUN_LOCAL=false
SKIP_JAR_SYNC=false
GIT_PULL=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--local)
		RUN_LOCAL=true
		shift
		;;
	--skip-jar-sync)
		SKIP_JAR_SYNC=true
		shift
		;;
	--pull)
		GIT_PULL=true
		shift
		;;
	-h | --help)
		sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "Unknown option: $1 (try --help)" >&2
		exit 1
		;;
	esac
done

build_jar_locally() {
	local server_dir="${REPO_ROOT}/server"
	echo "Building bootJar in ${server_dir}..." >&2
	# Gradle prints to stdout; keep this function's stdout for the JAR path only (see jar_path=$(build_jar_locally)).
	(cd "$server_dir" && ./gradlew bootJar --no-daemon) 1>&2
	local jar
	jar=$(find "$server_dir/build/libs" -maxdepth 1 -name "*.jar" ! -name "*-plain.jar" | head -1)
	if [[ -z "${jar}" || ! -f "${jar}" ]]; then
		echo "bootJar did not produce a fat JAR under ${server_dir}/build/libs" >&2
		exit 1
	fi
	printf '%s' "$jar"
}

ensure_jar_when_local() {
	if [[ -f "${SCRIPT_DIR}/application.jar" ]]; then
		return 0
	fi
	if [[ -x "${REPO_ROOT}/server/gradlew" ]]; then
		echo "No application.jar in ${SCRIPT_DIR}; building bootJar and copying here..." >&2
		local jar
		jar=$(build_jar_locally)
		cp "$jar" "${SCRIPT_DIR}/application.jar"
		return 0
	fi
	echo "Missing ${SCRIPT_DIR}/application.jar. Run a laptop deploy (without --local) to rsync the JAR, or copy a fat JAR here." >&2
	exit 1
}

maybe_git_pull() {
	local label="$1"
	if [[ "${GIT_PULL}" != true ]]; then
		return 0
	fi
	if [[ -d "${REPO_ROOT}/.git" ]]; then
		echo "git pull --ff-only (${REPO_ROOT}) [${label}]..." >&2
		git -C "${REPO_ROOT}" pull --ff-only
	else
		echo "Skipping git pull [${label}]: no .git at ${REPO_ROOT}." >&2
	fi
}

# Create remote staging dir if needed; print absolute path (for rsync / scp-style paths).
ensure_remote_staging_dir_abs() {
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

# Push a file over SSH stdin (avoids macOS scp "hostname contains invalid characters" with host:/abs/path).
ssh_push_file() {
	local host="$1"
	local local_file="$2"
	local remote_path="$3"
	local rq
	rq=$(printf '%q' "$remote_path")
	ssh -q "$host" "cat > ${rq}" <"${local_file}"
}

sync_staging_bundle() {
	local host="$1"
	local dest_abs="$2"
	local jar_path="${3:-}"

	local -a files=(
		"${SCRIPT_DIR}/docker-compose.yml"
		"${SCRIPT_DIR}/Dockerfile.api"
		"${SCRIPT_DIR}/Caddyfile"
		"${SCRIPT_DIR}/deploy.sh"
		"${SCRIPT_DIR}/.env.example"
	)

	echo "Rsync staging files → ${host}:${dest_abs}/" >&2
	rsync -avz -e ssh "${files[@]}" "${host}:${dest_abs}/"

	if [[ -n "${jar_path}" ]]; then
		echo "Copying application.jar → ${host}:${dest_abs}/application.jar" >&2
		ssh_push_file "$host" "${jar_path}" "${dest_abs}/application.jar"
	fi

	if [[ -f "${SCRIPT_DIR}/.env" ]]; then
		echo "Copying .env → ${host}:${dest_abs}/.env" >&2
		ssh_push_file "$host" "${SCRIPT_DIR}/.env" "${dest_abs}/.env"
	else
		echo "No local ${SCRIPT_DIR}/.env — ensure the server has .env (copy from .env.example once)." >&2
	fi
}

deploy_via_ssh() {
	local host="${WOLEH_STAGING_SSH:-woleh-staging}"
	host="${host//$'\r'/}"

	maybe_git_pull "laptop"

	local dest_abs
	dest_abs="$(ensure_remote_staging_dir_abs "$host")" || {
		echo "Could not create or resolve remote staging directory on ${host}." >&2
		if [[ -n "${WOLEH_STAGING_REMOTE_DIR:-}" ]]; then
			echo "  Check WOLEH_STAGING_REMOTE_DIR=${WOLEH_STAGING_REMOTE_DIR}" >&2
		else
			echo "  Default directory is \$HOME/woleh/deploy/staging" >&2
		fi
		exit 1
	}
	local rcd
	rcd=$(printf '%q' "$dest_abs")

	local jar_path=""
	if [[ "${SKIP_JAR_SYNC}" != true ]]; then
		jar_path="$(build_jar_locally)"
	else
		echo "Skipping Gradle and application.jar upload (--skip-jar-sync)." >&2
	fi

	sync_staging_bundle "$host" "$dest_abs" "$jar_path"

	local parts=(./deploy.sh --local)
	[[ "${GIT_PULL}" == true ]] && parts+=(--pull)

	local quoted=()
	for p in "${parts[@]}"; do
		quoted+=("$(printf '%q' "$p")")
	done
	local inner="${quoted[*]}"

	echo "Deploying via SSH (${host}), remote dir: ${dest_abs}" >&2
	exec ssh -t "${host}" "cd ${rcd} && exec ${inner}"
}

if [[ "${RUN_LOCAL}" != true ]]; then
	deploy_via_ssh
	exit 1
fi

# Prefer non-sudo when the user can reach the daemon; otherwise sudo (e.g. right after usermod -aG docker).
compose_cmd() {
	if docker info >/dev/null 2>&1; then
		docker compose "$@"
	elif sudo docker info >/dev/null 2>&1; then
		sudo docker compose "$@"
	else
		echo "Cannot reach Docker daemon (docker info failed). Try: sudo usermod -aG docker \"\$(id -un)\" then log in again." >&2
		return 1
	fi
}

docker_compose_usable() {
	docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

docker_compose_usable_sudo() {
	sudo docker info >/dev/null 2>&1 && sudo docker compose version >/dev/null 2>&1
}

# docker compose build requires buildx >= 0.17; Amazon Linux 2023 docker-buildx often reports v0.0.0+unknown.
needs_al2023_buildx_upgrade() {
	local line maj min
	line="$(sudo docker buildx version 2>/dev/null | head -1 || true)"
	[[ -z "${line}" ]] && return 0
	if [[ "${line}" == *unknown* ]] || [[ "${line}" == *0.0.0* ]]; then
		return 0
	fi
	if [[ "${line}" =~ v([0-9]+)\.([0-9]+) ]]; then
		maj="${BASH_REMATCH[1]}"
		min="${BASH_REMATCH[2]}"
		if [[ "${maj}" -gt 0 ]] || [[ "${min}" -ge 17 ]]; then
			return 1
		fi
	fi
	return 0
}

install_buildx_cli_plugin() {
	local arch barch ver plugin
	arch="$(uname -m)"
	case "${arch}" in
	x86_64) barch=amd64 ;;
	aarch64) barch=arm64 ;;
	*)
		echo "Cannot install docker-buildx: unsupported arch ${arch}" >&2
		return 1
		;;
	esac
	ver="v0.21.1"
	plugin=/usr/libexec/docker/cli-plugins/docker-buildx
	echo "Installing docker-buildx ${ver} (Compose needs buildx >= 0.17)..." >&2
	sudo mkdir -p /usr/libexec/docker/cli-plugins
	sudo curl -fsSL "https://github.com/docker/buildx/releases/download/${ver}/buildx-${ver}.linux-${barch}" -o "${plugin}.tmp"
	sudo mv "${plugin}.tmp" "${plugin}"
	sudo chmod +x "${plugin}"
}

ensure_al2023_buildx_if_needed() {
	[[ -r /etc/os-release ]] || return 0
	# shellcheck source=/dev/null
	. /etc/os-release
	[[ "${ID:-}" == "amzn" && "${VERSION_ID:-}" =~ ^2023 ]] || return 0
	sudo docker info >/dev/null 2>&1 || return 0
	if needs_al2023_buildx_upgrade; then
		install_buildx_cli_plugin || return 1
	fi
	return 0
}

# Install Docker + Compose v2 on Amazon Linux 2023 when missing (needs passwordless sudo, e.g. ec2-user).
ensure_docker() {
	if docker_compose_usable || docker_compose_usable_sudo; then
		ensure_al2023_buildx_if_needed || exit 1
		return 0
	fi

	local id vid
	if [[ ! -r /etc/os-release ]]; then
		echo "docker compose not found and /etc/os-release is missing; install Docker manually." >&2
		exit 1
	fi
	# shellcheck source=/dev/null
	. /etc/os-release
	id="${ID:-}"
	vid="${VERSION_ID:-}"
	if [[ "${id}" != "amzn" ]] || [[ ! "${vid}" =~ ^2023 ]]; then
		echo "docker compose not found. Automatic install supports Amazon Linux 2023 only (this host: ${id} ${vid})." >&2
		exit 1
	fi

	echo "Installing Docker on Amazon Linux 2023 (dnf + Compose plugin)..." >&2
	sudo dnf install -y docker
	sudo systemctl enable --now docker

	local arch plugin
	arch="$(uname -m)"
	plugin=/usr/libexec/docker/cli-plugins/docker-compose
	if [[ ! -x "${plugin}" ]]; then
		sudo mkdir -p /usr/libexec/docker/cli-plugins
		sudo curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}" -o "${plugin}.tmp"
		sudo mv "${plugin}.tmp" "${plugin}"
		sudo chmod +x "${plugin}"
	fi

	sudo usermod -aG docker "$(id -un)" 2>/dev/null || true

	if ! docker_compose_usable_sudo; then
		echo "Docker install finished but sudo docker compose is not working." >&2
		exit 1
	fi

	if docker_compose_usable_sudo && ! docker_compose_usable; then
		echo "Using sudo for docker compose in this session (log out and back in to use docker without sudo)." >&2
	fi

	ensure_al2023_buildx_if_needed || exit 1
}

ensure_docker

if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
	echo "Missing ${SCRIPT_DIR}/.env — copy .env.example, set POSTGRES_PASSWORD and JWT_SECRET, then retry." >&2
	exit 1
fi

ensure_jar_when_local

maybe_git_pull "server"

echo "Starting stack..." >&2
compose_cmd up -d --build --remove-orphans
