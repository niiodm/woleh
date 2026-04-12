# Woleh API (server)

Spring Boot **3.5** service for the Woleh transit app — Java **17**, Gradle **8** (wrapper included), main class `odm.clarity.woleh.WolehApplication`.

The monorepo overview, staging deploy, and shared env reference live in the [root `README.md`](../README.md). API contract and architecture: [`docs/`](../docs/).

## Requirements

- **JDK 17+**
- **Docker** with Compose v2 — for local PostgreSQL (default profile), unless you use the `dev` profile only

## Run locally

**Default (PostgreSQL):** from this directory, start the database, then the app. `spring-boot-docker-compose` can bring Postgres up automatically when the JVM starts if Docker is running and your working directory is `server/`.

```bash
docker compose up -d
./gradlew bootRun
```

The API listens on **http://localhost:8080** by default. REST is under **`/api/v1`**; WebSockets under **`/ws/v1/transit`**.

**Without Docker:** in-memory H2 only — fine for quick runs, not for integration tests or production-like behavior:

```bash
./gradlew bootRun --args='--spring.profiles.active=dev'
```

With the `dev` profile, OTP codes are logged to the console. For payment stub URLs on a **physical device**, set your machine’s LAN IP (see `build.gradle` `bootRun` and `application-dev.yml`):

```bash
./gradlew bootRun --args='--spring.profiles.active=dev' -PdevHost=192.168.1.42
# or: DEV_HOST=192.168.1.42 ./gradlew bootRun --args='--spring.profiles.active=dev'
```

**Disable auto-compose** when Postgres is already running or you are not using Docker:

```bash
SPRING_DOCKER_COMPOSE_ENABLED=false ./gradlew bootRun
```

If you run Gradle from the **repo root**, point Compose at this file:

```bash
DOCKER_COMPOSE_FILE=server/docker-compose.yml ./gradlew -p server bootRun
```

Database URL and credentials default to `localhost:5432`, database **`woleh`**, user/password **`woleh`** — see [`src/main/resources/application.yml`](src/main/resources/application.yml). Optional: copy [`.env.example`](../.env.example) to **`server/.env`** (or repo-root `.env`) and adjust `POSTGRES_*` / `POSTGRES_PORT` to match [`docker-compose.yml`](docker-compose.yml).

## Build and test

```bash
./gradlew build
./gradlew test
```

## Configuration

Most settings are in **`src/main/resources/application.yml`** (JWT under `woleh.jwt.*`, CORS under `woleh.cors.*`, OTP, rate limits, SMS, FCM). Production-critical env vars are summarized in the [root README](../README.md#configuration-api).

Health and metrics: **`/actuator/health`**, **`/actuator/health/readiness`**, **`/actuator/prometheus`**, etc. (see `management.*` in `application.yml`).

## Layout

| Path | Purpose |
|------|---------|
| [`src/main/java/odm/clarity/woleh/`](src/main/java/odm/clarity/woleh/) | Application code |
| [`src/main/resources/db/migration/`](src/main/resources/db/migration/) | Flyway migrations |
| [`api-tests/`](api-tests/) | `.http` files for manual API checks |
| [`Dockerfile`](Dockerfile) | Multi-stage image build |
| [`docker-compose.yml`](docker-compose.yml) | Local Postgres + optional OSM tile server (comments in file) |

Staging uses the **`staging`** profile ([`src/main/resources/application-staging.yml`](src/main/resources/application-staging.yml)) and the deploy flow in [`deploy/staging/`](../deploy/staging/).
