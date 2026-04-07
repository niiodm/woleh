# Woleh

Mono-repo for the **Woleh** transit app: Flutter client and Spring Boot API.

| Path | Description |
|------|-------------|
| [`docs/`](docs/) | PRD, architecture, API contract, ADRs |
| [`mobile/`](mobile/) | Flutter app — Dart package **`odm_clarity_woleh_mobile`**; Android/iOS **`odm.clarity.woleh_mobile`** |
| [`server/`](server/) | Spring Boot API — Java **`odm.clarity.woleh`** |
| [`server/docker-compose.yml`](server/docker-compose.yml) | Local PostgreSQL for development |
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
