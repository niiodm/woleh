# Woleh

Mono-repo for the **Woleh** transit app: Flutter client and Spring Boot API.

| Path | Description |
|------|-------------|
| [`docs/`](docs/) | PRD, architecture, API contract, ADRs |
| [`mobile/`](mobile/) | Flutter app — Dart package **`odm_clarity_woleh_mobile`**; Android/iOS **`odm.clarity.woleh_mobile`** |
| [`server/`](server/) | Spring Boot API — Java **`odm.clarity.woleh`** |
| [`server/docker-compose.yml`](server/docker-compose.yml) | Local PostgreSQL for development |
| [`deploy/staging/`](deploy/staging/) | Staging stack: API + Postgres + Caddy (TLS); [`connect-staging.sh`](deploy/staging/connect-staging.sh), [`logs-staging.sh`](deploy/staging/logs-staging.sh), [`app-logs-staging.sh`](deploy/staging/app-logs-staging.sh) |
| [`server/api-tests/`](server/api-tests/) | `.http` collections for manual API checks |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | CI (Gradle + Flutter) on push/PR to `main` |

## Configuration (API)

| Env | Purpose |
|-----|---------|
| `JWT_SECRET` | **Required in production** — HS256 signing key (use a long random value). |
| `JWT_ISSUER` | Optional (default `woleh`). |
| `JWT_ACCESS_TOKEN_TTL` | Optional ISO-8601 duration (default `PT24H`). |
| `CORS_ALLOWED_ORIGIN_PATTERNS` | Comma-separated patterns for browser clients (default local `http://localhost:*`, `http://127.0.0.1:*`). |

See `server/src/main/resources/application.yml` (`woleh.jwt.*`, `woleh.cors.*`).

## Staging (Docker Compose)

Public hostname: **`https://woleh.okaidarkomorgan.com`** (REST `/api/v1`, WebSocket `/ws/v1/transit`). Deploy on a VPS with Docker Compose v2.

1. Point **DNS** (A/AAAA) for `woleh.okaidarkomorgan.com` at the host. Allow inbound **TCP 80** and **443** (Postgres is not published to the host). The server needs **Docker** + **Compose v2**; **`deploy.sh --local`** can install them on **Amazon Linux 2023** via `dnf` and the official Compose CLI plugin (requires passwordless `sudo`, e.g. `ec2-user`). Your laptop uses **`rsync`** and **SSH** for file transfer (macOS/Linux include them).
2. **No git clone on the server** is required. [`deploy/staging/deploy.sh`](deploy/staging/deploy.sh) creates **`~/woleh/deploy/staging`** on first connect (override with **`WOLEH_STAGING_REMOTE_DIR`**), **rsync**s **`docker-compose.yml`**, **`Dockerfile.api`**, **`Caddyfile`**, **`deploy.sh`**, and **`.env.example`**, then streams the built **`application.jar`** and (if present) **`deploy/staging/.env`** over **SSH** (avoids macOS **scp**/**rsync** quirks for single-file remote paths).
3. On your **laptop**, copy [`deploy/staging/.env.example`](deploy/staging/.env.example) to **`deploy/staging/.env`** and set **`POSTGRES_PASSWORD`** and **`JWT_SECRET`** (and optional **`CORS_ALLOWED_ORIGIN_PATTERNS`**). The next deploy uploads **`.env`** to the server. Alternatively, create **`.env`** once on the server by hand; later laptop deploys without a local **`.env`** will not overwrite it.
4. **From your laptop** (SSH host **`WOLEH_STAGING_SSH`**, default **`woleh-staging`**), run **`./deploy/staging/deploy.sh`**. It **`git pull`**s the monorepo on the laptop when you pass **`--pull`** (if **`REPO_ROOT`** is a git checkout), runs **`./gradlew bootJar`**, **rsync**s the bundle, then **SSH** + **`./deploy.sh --local`**. **`./deploy.sh --skip-jar-sync`** skips Gradle and re-uploading the JAR. On the VPS alone, **`./deploy.sh --local`** runs Compose in the synced directory.

Smoke check: `curl -fsS https://woleh.okaidarkomorgan.com/actuator/health/readiness`.

**SSH and logs (from your laptop):** same env as deploy — **`WOLEH_STAGING_SSH`** (default **`woleh-staging`**), optional **`WOLEH_STAGING_REMOTE_DIR`**.

```bash
./deploy/staging/connect-staging.sh              # shell in ~/woleh/deploy/staging (or your override)
./deploy/staging/connect-staging.sh docker compose ps
./deploy/staging/logs-staging.sh                 # follow all service logs
./deploy/staging/logs-staging.sh -f --tail=50 api
./deploy/staging/app-logs-staging.sh             # follow API (Spring Boot) logs only
./deploy/staging/app-logs-staging.sh --tail=100
```

The staging API image is built from [`deploy/staging/Dockerfile.api`](deploy/staging/Dockerfile.api) (Java 17 JRE) using that **`application.jar`**. [`server/Dockerfile`](server/Dockerfile) remains a full multi-stage build for other uses. Staging uses profile **`staging`** ([`application-staging.yml`](server/src/main/resources/application-staging.yml)). Flyway runs on startup against the Compose Postgres volume.

**Scaling note:** Rate limits and WebSocket session state are **in-memory** on a single node ([`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)). Running more than one API replica without shared state changes that behavior.

**Map tiles:** Staging does not host map tiles. The mobile app defaults to a public OSM tile URL; for local dev you can still run the optional tile server in [`server/docker-compose.yml`](server/docker-compose.yml) and point **`OSM_TILE_URL_TEMPLATE`** at it.

## Continuous integration

On **push** and **pull request** to **`main`**, [GitHub Actions](.github/workflows/ci.yml) runs **`./gradlew build`** in `server/` and **`dart run build_runner build`**, **`flutter analyze`**, and **`flutter test`** in `mobile/`.

## Prerequisites

- **JDK 17+** and **Gradle** (wrapper included under `server/`)
- **Flutter** SDK (see `mobile/pubspec.yaml` for SDK constraint)
- **Docker** (Docker Compose v2) — for local **PostgreSQL**, or run the API with the **`dev`** profile only (in-memory H2; no Docker; see `server/src/main/resources/application-dev.yml`)

## Database (Docker Compose)

The default Spring profile expects Postgres at `localhost:5432`, database **`woleh`**, user/password **`woleh`** (see `application.yml`). **[`server/docker-compose.yml`](server/docker-compose.yml)** matches those defaults.

With **`./gradlew bootRun`** (default profile, no `dev`), the server includes **`spring-boot-docker-compose`** (development-only). On startup it runs **`docker compose up`** for that file (working directory should be **`server/`** — default for Gradle and typical IntelliJ Spring Boot run configs) if Docker is running and the stack is not already up, then waits for health checks. Containers are left running when the JVM exits (`lifecycle-management: start-only`).

To run **without** auto-compose (e.g. Postgres already running elsewhere, or no Docker):  
`SPRING_DOCKER_COMPOSE_ENABLED=false ./gradlew bootRun`

If the JVM working directory is **not** `server/` (e.g. repo root), set  
`DOCKER_COMPOSE_FILE=server/docker-compose.yml`.

Manual Compose:

```bash
cd server && docker compose up -d && docker compose ps
```

Optional: copy [`.env.example`](.env.example) to **`server/.env`** (Compose loads it from the project directory) or repo-root `.env`, and change `POSTGRES_*` or `POSTGRES_PORT` if `5432` is already in use. If you change credentials, set `DATABASE_URL`, `DATABASE_USER`, and `DATABASE_PASSWORD` when running the server.

## Quick commands

```bash
# API
cd server && docker compose up -d
cd server && ./gradlew build
cd server && ./gradlew bootRun

# Without Docker — in-memory DB only (not for real integration testing)
cd server && ./gradlew bootRun --args='--spring.profiles.active=dev'

# Mobile
cd mobile && flutter pub get
cd mobile && dart run build_runner build --delete-conflicting-outputs
cd mobile && flutter analyze && flutter test
```

Phase 0 implementation steps: [`docs/PHASE_0_IMPLEMENTATION.md`](docs/PHASE_0_IMPLEMENTATION.md).
