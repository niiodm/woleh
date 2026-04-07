# Phase 0 — Implementation breakdown (codable steps)

This document turns [PRD.md](./PRD.md) §10 **Phase 0 — Foundation** into ordered, implementable work. **Exit criterion:** a user can **sign in** (phone OTP) and **see protected content** (authenticated session + profile / `GET /me`).

**References:** [ARCHITECTURE.md](./ARCHITECTURE.md), [API_CONTRACT.md](./API_CONTRACT.md), [PLACE_NAMES.md](./PLACE_NAMES.md), [ADR 0002](./adr/0002-otp-policy.md) (OTP), [ADR 0003](./adr/0003-account-creation-and-auth-flow.md) (account timing, `flow`).

### Locked identifiers (v1)

| Artifact | Value |
|----------|--------|
| **Server (Gradle / JVM)** | Base package **`odm.clarity.woleh`** — Spring Boot main class, Java/Kotlin sources, and tests live under this namespace (e.g. `odm.clarity.woleh.WolehApplication`). |
| **Flutter (Dart package)** | **`odm.clarity.woleh_mobile`** — `name:` in `pubspec.yaml`; Android `applicationId` / iOS bundle id should align with product conventions (often the same string or `odm.clarity.woleh_mobile` with platform suffixes as required by stores). |
| **Riverpod** | **Codegen on** — use `riverpod_annotation` + `riverpod_generator` + `build_runner`; define providers with `@riverpod` / `@Riverpod` and generated `*.g.dart` files. |

---

## 1. Scope

| In scope (Phase 0) | Deferred |
|--------------------|----------|
| Mono-repo layout (`mobile/`, `server/`, `server/api-tests/`, `docs/`) | WebSocket `/ws/v1/transit` |
| CI pipeline (build + tests) | Place-name lists (`/me/places/*`) |
| REST: `POST /auth/send-otp`, `POST /auth/verify-otp` | Payment / checkout |
| REST: `GET /me`, `PATCH /me/profile` | Rate limiting beyond OTP (see ADR 0002) |
| JWT access tokens; public `GET /actuator/health` (or equivalent) | Refresh tokens (not in [API_CONTRACT.md](./API_CONTRACT.md) v1; define re-auth policy: e.g. OTP again when access JWT expires) |
| Free-tier entitlements stub in `GET /me` (permissions + limits per [API_CONTRACT.md](./API_CONTRACT.md) §4) | Paid tier, webhooks, grace period logic (Phase 1+) |
| Flutter: OTP flow, token storage, protected screen(s) showing `me` data | Plans UI beyond optional stub |

**Optional within Phase 0** (if you want the client to exercise the public catalog early): seed and expose **`GET /api/v1/subscription/plans`** with static JSON per [API_CONTRACT.md](./API_CONTRACT.md) §6.5. Not required for the Phase 0 exit criterion if the app does not navigate to plans yet.

---

## 2. Repository and tooling

### Step 2.1 — Create layout

- Add **`server/`**: Spring Boot 3.x, Java 17+, **Gradle**; root Java/Kotlin package **`odm.clarity.woleh`**.
- Add **`mobile/`**: Flutter project **`odm.clarity.woleh_mobile`** with flavors or `--dart-define` for `API_BASE_URL` ([ARCHITECTURE.md](./ARCHITECTURE.md) §4.1, §4.4).
- Add **`server/api-tests/`**: `.http` files (or Bruno/Insomnia) for manual contract checks; wire env for base URL and a test phone.
- Keep **`docs/`** as the living spec; update cross-links when code exists.

**Done when:** both projects build locally from a clean clone (`./gradlew build` / `dart run build_runner build` where needed / `flutter test`).

### Step 2.2 — CI

- Add a workflow (e.g. GitHub Actions) that:
  - Checks out the repo.
  - Builds and tests the **server** (unit tests; DB tests via Testcontainers only if you add them in this phase).
  - Runs **`flutter analyze`** and **`flutter test`** for **mobile**.
- Cache dependencies (Gradle, Pub) to keep runs fast; run **`build_runner`** in CI when codegen is part of the mobile build (or commit `*.g.dart` per team policy).

**Done when:** CI is green on `main` for the above steps.

---

## 3. Server (Spring Boot)

Implement behind prefix **`/api/v1`** with the **envelope** from [API_CONTRACT.md](./API_CONTRACT.md) §2 (`result`, `message`, `data`).

### Step 3.1 — Bootstrap and configuration

- Spring Web, Spring Security, Spring Data JPA, validation, Actuator.
- **`application.yml`**: datasource (PostgreSQL), JWT signing secret/issuer/TTL via env vars, profile for `dev` (e.g. log SQL).
- **Flyway** (or Liquibase) under `server/src/main/resources/db/migration`.

**Done when:** app starts against a local Postgres; migrations apply cleanly.

### Step 3.2 — Database schema (minimal)

- **`users`**: `id`, `phone_e164` (unique), `display_name` (nullable), audit timestamps as needed.
- **OTP storage** (table or dedicated store): link to pending verification by `phone_e164`, **hashed** OTP ([ADR 0002](./adr/0002-otp-policy.md)), `expires_at`, `attempt_count`, consumed flag.
- No subscription/billing tables required for Phase 0 if **`GET /me`** computes **free-tier** entitlements in code (permissions + limits per [API_CONTRACT.md](./API_CONTRACT.md) §4).

**Done when:** entities map to tables; user created **only after successful OTP verify** ([ADR 0003](./adr/0003-account-creation-and-auth-flow.md)).

### Step 3.3 — Global API behavior

- **`@ControllerAdvice`** (or equivalent): map exceptions to HTTP status and error envelope §2.2; include `message` (and optional `code` later).
- **CORS**: allow the Flutter web/debug origins you use; tighten for prod.
- **Security filter chain**:
  - **Permit without auth:** `POST /api/v1/auth/send-otp`, `POST /api/v1/auth/verify-otp`, `GET /api/v1/subscription/plans` (if implemented), **`/actuator/health`** (or `/health` if proxied).
  - **JWT** on `/api/v1/me/**` and other protected routes.

**Done when:** 401 for missing/invalid JWT on protected routes; 404 routes return consistent JSON errors.

### Step 3.4 — OTP: `POST /api/v1/auth/send-otp`

- Validate **`phoneE164`** (E.164; Ghana-focused `+233` in product copy, but accept valid E.164).
- Generate 6-digit OTP; hash and store with TTL **5 minutes** ([ADR 0002](./adr/0002-otp-policy.md)).
- **Rate limit:** 3 successful sends per number per rolling hour → **429** with error envelope.
- **Dev:** log OTP to console or return in a dev-only header **only** behind a flag (never in production).
- **Prod:** integrate SMS adapter behind an interface (stub implementation acceptable for Phase 0 if you only run in dev).

**Done when:** contract response includes `expiresInSeconds: 300` ([API_CONTRACT.md](./API_CONTRACT.md) §6.1).

### Step 3.5 — OTP: `POST /api/v1/auth/verify-otp`

- Validate body; load pending OTP by phone; check expiry and **≤ 5** failed attempts ([ADR 0002](./adr/0002-otp-policy.md)).
- On success:
  - If user exists for phone → **`flow: "login"`** ([ADR 0003](./adr/0003-account-creation-and-auth-flow.md)).
  - If not → **create user**, then **`flow: "signup"`**.
- Issue **JWT** (`sub` = user id, standard claims, expiry aligned with `expiresInSeconds` in response).
- Mark OTP consumed; **repeat verify** on consumed OTP → **400**, no double user creation ([ADR 0003](./adr/0003-account-creation-and-auth-flow.md)).

**Done when:** response matches [API_CONTRACT.md](./API_CONTRACT.md) §6.2 (`accessToken`, `tokenType`, `expiresInSeconds`, `userId`, `flow`).

### Step 3.6 — Profile and session: `GET /api/v1/me`

- Require valid JWT; load user by id from principal.
- Return **`profile`** (e.g. `userId`, `phoneE164`, `displayName`) plus **entitlements**: `permissions`, `tier`, `limits`, `subscription` stub ([API_CONTRACT.md](./API_CONTRACT.md) §4, §6.3).
- For Phase 0, **free tier** defaults from [PRD.md](./PRD.md) §13.1 (e.g. `woleh.account.profile`, `woleh.plans.read`, `woleh.place.watch`; watch cap 5; no broadcast permission).

**Done when:** mobile can render name + permission list from one call.

### Step 3.7 — `PATCH /api/v1/me/profile`

- Require JWT + permission check for **`woleh.account.profile`** (method security or explicit check).
- Partial update **`displayName`** (and any other allowed fields); reject immutable fields (e.g. phone) with **400** if sent.

**Done when:** after signup, client can set name and see it on next `GET /me`.

### Step 3.8 — Health

- Expose **`/actuator/health`** (or documented path) **without** JWT; include DB check if trivial (optional for Phase 0).

**Done when:** orchestrator or `curl` can verify liveness/readiness.

### Step 3.9 — Tests and API artifacts

- Unit tests: OTP hashing, verify attempt limits, `flow` branching.
- Integration tests: `@WebMvcTest` or `@SpringBootTest` with test DB for auth + `/me` (minimal).
- **`server/api-tests/*.http`**: send-otp → verify-otp → GET me → PATCH profile.

**Done when:** CI runs these tests successfully.

---

## 4. Mobile (Flutter)

### Step 4.1 — Core wiring

- Dependencies: **Riverpod with codegen** (`flutter_riverpod`, `riverpod_annotation`, `riverpod_generator`, `build_runner`), **Dio**, **flutter_secure_storage**, **go_router** ([ARCHITECTURE.md](./ARCHITECTURE.md) §4.1).
- Prefer **`@riverpod`** / **`@Riverpod`** providers (notifier + async providers as needed); run **`dart run build_runner watch`** during development.
- **`lib/core/`**: `ApiClient` (base URL from `--dart-define`), interceptor attaching `Authorization: Bearer`, error mapping to typed failures (401/403/429/5xx).
- **`lib/app/`**: router with **auth redirect**: unauthenticated users only on `/auth/*`; authenticated users skip auth routes.

**Done when:** toggling a “fake token” proves redirects work (before real API).

### Step 4.2 — Auth screens

- Screen A: enter **phone** (validate E.164 UX for Ghana).
- Call **`POST .../auth/send-otp`**; show countdown / resend respecting rate limits (surface **429**).
- Screen B: enter **OTP**; call **`POST .../auth/verify-otp`**; persist **`accessToken`** in secure storage.
- Branch on **`flow`**: `signup` → optional profile completion (or inline name field); `login` → home.

**Done when:** end-to-end against dev server completes login and signup paths.

### Step 4.3 — Session and protected UI

- On app start: if token present, **validate** with **`GET /me`** (or treat 401 as logout).
- **Home (or “signed in”) screen**: display at least **`displayName`**, **phone**, and a short **permissions** summary from `data` (proves protected fetch).
- **Logout:** delete token; clear in-memory state; navigate to auth.

**Done when:** this matches the Phase 0 **exit criterion** (sign in + see protected content).

### Step 4.4 — Profile edit (minimal)

- Form bound to **`PATCH /me/profile`**; on success refresh **`GET /me`** or update local state.

**Done when:** name changes persist across restart (via re-fetch).

### Step 4.5 — Tests

- Widget or golden tests for auth screens (mock repository).
- Unit tests for phone validation and redirect logic.

---

## 5. Definition of done (Phase 0)

- [ ] CI runs server + mobile checks on every push to `main`.
- [ ] New user: **send-otp** → **verify-otp** (`flow: signup`) → optional **PATCH profile** → **GET /me** shows free-tier entitlements.
- [ ] Returning user: **verify-otp** returns `flow: login`; **GET /me** works.
- [ ] Invalid/expired JWT yields **401**; client returns to auth.
- [ ] Health endpoint responds without auth.
- [ ] `.http` collection documents the happy path for manual QA.

---

## 6. Document history

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2026-04-07 | Initial Phase 0 codable breakdown |
| 0.2 | 2026-04-07 | Locked Gradle package `odm.clarity.woleh`, Flutter `odm.clarity.woleh_mobile`, Riverpod codegen |
| 0.3 | 2026-04-07 | Restored file (was missing from tree); content unchanged from v0.2 |

When Phase 0 is complete, update [PRD.md](./PRD.md) or a project README with “Phase 0 complete” and any deviations (e.g. refresh-token policy).
