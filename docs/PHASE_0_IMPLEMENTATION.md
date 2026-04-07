# Phase 0 — Implementation breakdown (codable steps)

This document turns [PRD.md](./PRD.md) §10 **Phase 0 — Foundation** into ordered, implementable work. **Exit criterion:** a user can **sign in** (phone OTP) and **see protected content** (authenticated session + profile / `GET /me`).

**References:** [ARCHITECTURE.md](./ARCHITECTURE.md), [API_CONTRACT.md](./API_CONTRACT.md), [PLACE_NAMES.md](./PLACE_NAMES.md), [ADR 0002](./adr/0002-otp-policy.md) (OTP), [ADR 0003](./adr/0003-account-creation-and-auth-flow.md) (account timing, `flow`).

### Locked identifiers (v1)

| Artifact | Value |
|----------|--------|
| **Server (Gradle / JVM)** | Base package **`odm.clarity.woleh`** — Spring Boot main class, Java/Kotlin sources, and tests live under this namespace (e.g. `odm.clarity.woleh.WolehApplication`). |
| **Flutter (Dart package)** | **`odm_clarity_woleh_mobile`** — `name:` in `pubspec.yaml` (Dart allows only `a-z0-9_`). Android **`applicationId`** / iOS bundle id: **`odm.clarity.woleh_mobile`**. |
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

**Implementation:** [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) — jobs **Server (Gradle)** and **Mobile (Flutter)** on push/PR to `main`.

**Done when:** CI is green on `main` for the above steps.

---

## 3. Server (Spring Boot)

Implement behind prefix **`/api/v1`** with the **envelope** from [API_CONTRACT.md](./API_CONTRACT.md) §2 (`result`, `message`, `data`).

### Step 3.1 — Bootstrap and configuration

- Spring Web, Spring Security, Spring Data JPA, validation, Actuator.
- **`application.yml`**: datasource (PostgreSQL), JWT signing secret/issuer/TTL via env vars, profile for `dev` (e.g. log SQL).
- **Flyway** (or Liquibase) under `server/src/main/resources/db/migration`.

**Implementation:** `woleh.jwt.*` (`WolehJwtProperties`), JJWT on the classpath, `spring-boot-configuration-processor`, baseline `db/migration/V1__baseline.sql`, **`dev`** profile SQL logging (`application-dev.yml`). Env: `JWT_SECRET`, `JWT_ISSUER`, `JWT_ACCESS_TOKEN_TTL`.

**Done when:** app starts against a local Postgres; migrations apply cleanly.

### Step 3.2 — Database schema (minimal)

- **`users`**: `id`, `phone_e164` (unique), `display_name` (nullable), audit timestamps as needed.
- **OTP storage** (table or dedicated store): link to pending verification by `phone_e164`, **hashed** OTP ([ADR 0002](./adr/0002-otp-policy.md)), `expires_at`, `attempt_count`, consumed flag.
- No subscription/billing tables required for Phase 0 if **`GET /me`** computes **free-tier** entitlements in code (permissions + limits per [API_CONTRACT.md](./API_CONTRACT.md) §4).

**Implementation:** Flyway **`V2__users_and_otp_challenges.sql`** (`users`, `otp_challenges`); JPA entities [`User`](../server/src/main/java/odm/clarity/woleh/model/User.java), [`OtpChallenge`](../server/src/main/java/odm/clarity/woleh/model/OtpChallenge.java); [`UserRepository`](../server/src/main/java/odm/clarity/woleh/repository/UserRepository.java), [`OtpChallengeRepository`](../server/src/main/java/odm/clarity/woleh/repository/OtpChallengeRepository.java). User rows are created only in verify-otp success path (step 3.5).

**Done when:** entities map to tables; user created **only after successful OTP verify** ([ADR 0003](./adr/0003-account-creation-and-auth-flow.md)).

### Step 3.3 — Global API behavior

- **`@ControllerAdvice`** (or equivalent): map exceptions to HTTP status and error envelope §2.2; include `message` (and optional `code` later).
- **CORS**: allow the Flutter web/debug origins you use; tighten for prod.
- **Security filter chain**:
  - **Permit without auth:** `POST /api/v1/auth/send-otp`, `POST /api/v1/auth/verify-otp`, `GET /api/v1/subscription/plans` (if implemented), **`/actuator/health`** (or `/health` if proxied).
  - **JWT** on `/api/v1/me/**` and other protected routes.

**Implementation:** [`ApiEnvelope`](../server/src/main/java/odm/clarity/woleh/api/dto/ApiEnvelope.java); [`GlobalExceptionHandler`](../server/src/main/java/odm/clarity/woleh/api/error/GlobalExceptionHandler.java); [`JwtService`](../server/src/main/java/odm/clarity/woleh/security/JwtService.java) + [`JwtAuthenticationFilter`](../server/src/main/java/odm/clarity/woleh/security/JwtAuthenticationFilter.java); [`SecurityConfig`](../server/src/main/java/odm/clarity/woleh/config/SecurityConfig.java) (stateless JWT, JSON 401/403, CORS via `woleh.cors.allowed-origin-patterns` / `CORS_ALLOWED_ORIGIN_PATTERNS`); `spring.mvc.throw-exception-if-no-handler-found` + minimal placeholder [`MeController`](../server/src/main/java/odm/clarity/woleh/api/MeController.java); tests [`ApiSecurityIntegrationTest`](../server/src/test/java/odm/clarity/woleh/api/ApiSecurityIntegrationTest.java).

**Done when:** 401 for missing/invalid JWT on protected routes; 404 routes return consistent JSON errors.

### Step 3.4 — OTP: `POST /api/v1/auth/send-otp` ✅

- Validate **`phoneE164`** (E.164; Ghana-focused `+233` in product copy, but accept valid E.164).
- Generate 6-digit OTP; hash and store with TTL **5 minutes** ([ADR 0002](./adr/0002-otp-policy.md)).
- **Rate limit:** 3 successful sends per number per rolling hour → **429** with error envelope.
- **Dev:** log OTP to console or return in a dev-only header **only** behind a flag (never in production).
- **Prod:** integrate SMS adapter behind an interface (stub implementation acceptable for Phase 0 if you only run in dev).

**Implementation:** [`SendOtpRequest`](../server/src/main/java/odm/clarity/woleh/auth/dto/SendOtpRequest.java) / [`SendOtpResponse`](../server/src/main/java/odm/clarity/woleh/auth/dto/SendOtpResponse.java); [`OtpService`](../server/src/main/java/odm/clarity/woleh/auth/service/OtpService.java) (generate, BCrypt-hash, persist, `woleh.otp.dev-log-otp` flag); [`AuthController`](../server/src/main/java/odm/clarity/woleh/auth/AuthController.java); [`SmsAdapter`](../server/src/main/java/odm/clarity/woleh/sms/SmsAdapter.java) + [`StubSmsAdapter`](../server/src/main/java/odm/clarity/woleh/sms/StubSmsAdapter.java); [`OtpProperties`](../server/src/main/java/odm/clarity/woleh/config/OtpProperties.java) (`woleh.otp.*`); [`RateLimitedException`](../server/src/main/java/odm/clarity/woleh/common/error/RateLimitedException.java) → 429 in `GlobalExceptionHandler`; tests [`SendOtpIntegrationTest`](../server/src/test/java/odm/clarity/woleh/auth/SendOtpIntegrationTest.java).

**Done when:** contract response includes `expiresInSeconds: 300` ([API_CONTRACT.md](./API_CONTRACT.md) §6.1). ✅

### Step 3.5 — OTP: `POST /api/v1/auth/verify-otp` ✅

- Validate body; load pending OTP by phone; check expiry and **≤ 5** failed attempts ([ADR 0002](./adr/0002-otp-policy.md)).
- On success:
  - If user exists for phone → **`flow: "login"`** ([ADR 0003](./adr/0003-account-creation-and-auth-flow.md)).
  - If not → **create user**, then **`flow: "signup"`**.
- Issue **JWT** (`sub` = user id, standard claims, expiry aligned with `expiresInSeconds` in response).
- Mark OTP consumed; **repeat verify** on consumed OTP → **400**, no double user creation ([ADR 0003](./adr/0003-account-creation-and-auth-flow.md)).

**Implementation:** [`VerifyOtpRequest`](../server/src/main/java/odm/clarity/woleh/auth/dto/VerifyOtpRequest.java) / [`VerifyOtpResponse`](../server/src/main/java/odm/clarity/woleh/auth/dto/VerifyOtpResponse.java); [`VerifyOtpResult`](../server/src/main/java/odm/clarity/woleh/auth/service/VerifyOtpResult.java); [`OtpService.verifyOtp`](../server/src/main/java/odm/clarity/woleh/auth/service/OtpService.java) (attempt tracking, user create/lookup, consumed guard); [`InvalidOtpException`](../server/src/main/java/odm/clarity/woleh/common/error/InvalidOtpException.java) → 400 in `GlobalExceptionHandler`; [`AuthController.verifyOtp`](../server/src/main/java/odm/clarity/woleh/auth/AuthController.java); tests [`VerifyOtpIntegrationTest`](../server/src/test/java/odm/clarity/woleh/auth/VerifyOtpIntegrationTest.java).

**Done when:** response matches [API_CONTRACT.md](./API_CONTRACT.md) §6.2 (`accessToken`, `tokenType`, `expiresInSeconds`, `userId`, `flow`). ✅

### Step 3.6 — Profile and session: `GET /api/v1/me` ✅

- Require valid JWT; load user by id from principal.
- Return **`profile`** (e.g. `userId`, `phoneE164`, `displayName`) plus **entitlements**: `permissions`, `tier`, `limits`, `subscription` stub ([API_CONTRACT.md](./API_CONTRACT.md) §4, §6.3).
- For Phase 0, **free tier** defaults from [PRD.md](./PRD.md) §13.1 (e.g. `woleh.account.profile`, `woleh.plans.read`, `woleh.place.watch`; watch cap 5; no broadcast permission).

**Implementation:** [`MeResponse`](../server/src/main/java/odm/clarity/woleh/api/dto/MeResponse.java) (profile, limits, subscription nested records); [`MeController`](../server/src/main/java/odm/clarity/woleh/api/MeController.java) (loads `User` by JWT principal, returns free-tier entitlements); [`UserNotFoundException`](../server/src/main/java/odm/clarity/woleh/common/error/UserNotFoundException.java) → 404 in `GlobalExceptionHandler`; tests [`MeIntegrationTest`](../server/src/test/java/odm/clarity/woleh/api/MeIntegrationTest.java).

**Done when:** mobile can render name + permission list from one call. ✅

### Step 3.7 — `PATCH /api/v1/me/profile` ✅

- Require JWT + permission check for **`woleh.account.profile`** (method security or explicit check).
- Partial update **`displayName`** (and any other allowed fields); reject immutable fields (e.g. phone) with **400** if sent.

**Implementation:** [`PatchProfileRequest`](../server/src/main/java/odm/clarity/woleh/api/dto/PatchProfileRequest.java) (`displayName` with size validation; `phoneE164` annotated `@AssertNull` → 400 if supplied); [`MeController.patchProfile`](../server/src/main/java/odm/clarity/woleh/api/MeController.java) (partial update — only writes fields that are non-null in the request; returns full `MeResponse`); tests [`PatchProfileIntegrationTest`](../server/src/test/java/odm/clarity/woleh/api/PatchProfileIntegrationTest.java).

**Done when:** after signup, client can set name and see it on next `GET /me`. ✅

### Step 3.8 — Health ✅

- Expose **`/actuator/health`** (or documented path) **without** JWT; include DB check if trivial (optional for Phase 0).

**Implementation:** `management.endpoint.health.show-details/show-components: always` (override via `HEALTH_SHOW_DETAILS`); liveness/readiness probes enabled at `/actuator/health/liveness` and `/actuator/health/readiness` (`HEALTH_PROBES_ENABLED`); DB component auto-included by Spring Boot Actuator; tests [`HealthIntegrationTest`](../server/src/test/java/odm/clarity/woleh/api/HealthIntegrationTest.java).

**Done when:** orchestrator or `curl` can verify liveness/readiness. ✅

### Step 3.9 — Tests and API artifacts ✅

- Unit tests: OTP hashing, verify attempt limits, `flow` branching.
- Integration tests: `@WebMvcTest` or `@SpringBootTest` with test DB for auth + `/me` (minimal).
- **`server/api-tests/*.http`**: send-otp → verify-otp → GET me → PATCH profile.

**Implementation:** [`OtpServiceTest`](../server/src/test/java/odm/clarity/woleh/auth/service/OtpServiceTest.java) — 15 Mockito unit tests covering OTP format (6 digits), BCrypt hash storage, TTL, SMS dispatch, rate-limit guard, expiry/exhaustion/wrong-OTP/consumed paths, signup vs login flow branching, user creation idempotency; [`phase0.http`](../server/api-tests/phase0.http) reorganised into four numbered sections (health → send-otp → verify-otp → GET /me → PATCH profile) with `@token` variable; [`http-client.env.json`](../server/api-tests/http-client.env.json) added for IntelliJ HTTP Client `dev`/`staging` environments.

**Done when:** CI runs these tests successfully. ✅

---

## 4. Mobile (Flutter)

### Step 4.1 — Core wiring ✅

- Dependencies: **Riverpod with codegen** (`flutter_riverpod`, `riverpod_annotation`, `riverpod_generator`, `build_runner`), **Dio**, **flutter_secure_storage**, **go_router** ([ARCHITECTURE.md](./ARCHITECTURE.md) §4.1).
- Prefer **`@riverpod`** / **`@Riverpod`** providers (notifier + async providers as needed); run **`dart run build_runner watch`** during development.
- **`lib/core/`**: `ApiClient` (base URL from `--dart-define`), interceptor attaching `Authorization: Bearer`, error mapping to typed failures (401/403/429/5xx).
- **`lib/app/`**: router with **auth redirect**: unauthenticated users only on `/auth/*`; authenticated users skip auth routes.

**Done when:** toggling a “fake token” proves redirects work (before real API). ✅

**Implementation:** [`app_error.dart`](../mobile/lib/core/app_error.dart) (sealed failure hierarchy: `UnauthorizedError`, `ForbiddenError`, `RateLimitedError`, `ServerError`, `NetworkError`, `UnknownError`); [`auth_token_storage.dart`](../mobile/lib/core/auth_token_storage.dart) (`AuthTokenStorage` + `keepAlive` providers); [`auth_state.dart`](../mobile/lib/core/auth_state.dart) (`AuthState` async notifier — `setToken`/`signOut`); [`api_client.dart`](../mobile/lib/core/api_client.dart) (`ApiClient` wrapping Dio with `_AuthInterceptor` and `_ErrorInterceptor`, `API_BASE_URL` via `--dart-define`); [`router.dart`](../mobile/lib/app/router.dart) (`GoRouter` keepAlive provider + `_RouterNotifier` bridging `authStateProvider` changes to `refreshListenable`; `/auth/phone` → `PhoneScreen`, `/home` → `HomeScreen`); stub screens with fake-token toggle and sign-out; `main.dart` updated to `MaterialApp.router`; widget tests verify both redirect paths.

### Step 4.2 — Auth screens ✅

- Screen A: enter **phone** (validate E.164 UX for Ghana).
- Call **`POST .../auth/send-otp`**; show countdown / resend respecting rate limits (surface **429**).
- Screen B: enter **OTP**; call **`POST .../auth/verify-otp`**; persist **`accessToken`** in secure storage.
- Branch on **`flow`**: `signup` → optional profile completion (or inline name field); `login` → home.

**Implementation:** [`auth_dto.dart`](../mobile/lib/features/auth/data/auth_dto.dart) (`SendOtpResponse`, `VerifyOtpResponse`); [`auth_repository.dart`](../mobile/lib/features/auth/data/auth_repository.dart) (`sendOtp`, `verifyOtp`, keepAlive provider); [`phone_utils.dart`](../mobile/lib/core/phone_utils.dart) (`normalizePhone`, `isValidE164`, Ghana `+233` default); [`phone_notifier.dart`](../mobile/lib/features/auth/presentation/phone_notifier.dart) + [`phone_screen.dart`](../mobile/lib/features/auth/presentation/phone_screen.dart) (E.164 text field, loading/error/429 states, normalizes `0XXXXXXXXX` → `+233...`); [`otp_notifier.dart`](../mobile/lib/features/auth/presentation/otp_notifier.dart) (family by `phoneE164`, countdown `Timer`, resend, verify); [`otp_screen.dart`](../mobile/lib/features/auth/presentation/otp_screen.dart) (6-digit field, live countdown, resend button); [`me_repository.dart`](../mobile/lib/features/me/data/me_repository.dart) (`patchDisplayName`); [`setup_name_screen.dart`](../mobile/lib/features/auth/presentation/setup_name_screen.dart) (`SetupNameNotifier`, save/skip → `/home`); router updated: `/auth/otp` (phone+expiresInSeconds via `extra`), `/auth/setup-name` (allowed when authenticated); redirect allows setup-name for authenticated users.

**Done when:** end-to-end against dev server completes login and signup paths. ✅

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
| 0.4 | 2026-04-07 | Step 3.4 implemented: send-otp endpoint, OtpService, SmsAdapter, OtpProperties, RateLimitedException |
| 0.5 | 2026-04-07 | Step 3.5 implemented: verify-otp endpoint, VerifyOtpResult, InvalidOtpException, user create/lookup |
| 0.6 | 2026-04-07 | Step 3.6 implemented: GET /me with full profile + free-tier entitlements, MeResponse, UserNotFoundException |
| 0.7 | 2026-04-07 | Step 3.7 implemented: PATCH /me/profile with displayName update and immutable-field guard |
| 0.8 | 2026-04-07 | Step 3.8 implemented: health details, liveness/readiness probes, HealthIntegrationTest |
| 0.9 | 2026-04-07 | Step 3.9 implemented: OtpServiceTest unit tests, phase0.http reorganised, http-client.env.json |
| 1.0 | 2026-04-07 | Step 4.1 implemented: core wiring — ApiClient, AuthTokenStorage, AuthState, GoRouter with auth redirect, stub screens, widget tests |
| 1.1 | 2026-04-07 | Step 4.2 implemented: auth screens — PhoneScreen, OtpScreen (countdown + resend), SetupNameScreen (signup branch), AuthRepository, MeRepository.patchDisplayName |

When Phase 0 is complete, update [PRD.md](./PRD.md) or a project README with “Phase 0 complete” and any deviations (e.g. refresh-token policy).
