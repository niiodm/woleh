# Phase 3 — Implementation breakdown (codable steps)

This document turns [PRD.md](./PRD.md) §10 **Phase 3 — Hardening** into ordered, implementable work. **Exit criterion:** SLOs met (p95 < 500 ms for core paths under nominal load); rate limits active on high-frequency endpoints; structured logs with correlation IDs deployed; Actuator health + Micrometer metrics exportable; runbooks for incidents written.

**References:** [ARCHITECTURE.md](./ARCHITECTURE.md) §5.4, §5.7, [API_CONTRACT.md](./API_CONTRACT.md), [PRD.md](./PRD.md) §7.3 (FR-R2), §7.5 (FR-L3), §7.6 (FR-N1), §7.7 (FR-O1), §8 (NFR-1–NFR-3), §13.7 (offline), [Phase 2 implementation](./PHASE_2_IMPLEMENTATION.md).

### Locked identifiers (carry-over from Phase 0–2)

| Artifact | Value |
|----------|--------|
| **Server base package** | `odm.clarity.woleh` |
| **Flutter package** | `odm_clarity_woleh_mobile` |
| **Riverpod** | Codegen on — `@riverpod` / `@Riverpod` + `*.g.dart` |
| **WS path** | `/ws/v1/transit` |
| **Error envelope** | `{ "result": "ERROR", "message": "...", "code": "..." }` |

---

## 1. Scope

| In scope (Phase 3) | Deferred / out of scope |
|--------------------|-------------------------|
| Per-user rate limiting on place list PUTs; per-IP OTP send limiting | Redis-backed rate limiter (single-node in-memory is sufficient for v1 — ADR needed before multi-instance) |
| Spring Boot Actuator: health + info endpoints | Admin / support UI (FR-O2 — still P2) |
| Micrometer custom metrics: WS sessions, match duration, place list writes, API error rate | Full APM agent or distributed tracing (out of scope for v1) |
| Structured logging: `X-Request-Id` correlation + MDC `userId` | Log aggregation infrastructure (depends on deployment environment) |
| JWT token refresh (`POST /api/v1/auth/refresh`) — FR-A2 still deferred from Phases 0–2 | OTP provider upgrade to production SMS (ongoing; not a Phase 3 blocker) |
| Offline read-only cache: cached profile + place lists displayed when offline | Offline mutations (PRD §13.7 explicitly excludes these) |
| WS connection state indicator in UI (NFR-2: graceful degradation) | |
| Push notifications for match events + subscription expiry (FR-N1, P2) | Real FCM credentials — feature-flagged off until configured |
| SLO baseline document | Formal SLA commitment (product/legal decision) |
| Incident runbooks | |

---

## 2. Server (Spring Boot)

### Step 2.1 — Rate limiting on high-frequency endpoints ✅

Implement a `RateLimiter @Component` using a `ConcurrentHashMap<String, TokenBucketState>` (in-memory, single-node). The key is `"userId:<userId>:<endpoint>"` for authenticated endpoints and `"ip:<remoteAddr>:otp-send"` for the pre-auth OTP path. Expose config via `application.yml` so limits can be adjusted without a code change:

```yaml
woleh:
  ratelimit:
    place-list:
      requests-per-minute: 10   # per user, per list type
    otp-send:
      requests-per-hour: 5      # per IP
```

Apply to:
- `PUT /api/v1/me/places/watch` — 10 req/min per user
- `PUT /api/v1/me/places/broadcast` — 10 req/min per user
- `POST /api/v1/auth/send-otp` — 5 req/hour per IP

Return `429 Too Many Requests` with body:
```json
{ "result": "ERROR", "code": "RATE_LIMITED", "message": "Too many requests. Please try again later." }
```
Include a `Retry-After: <seconds>` response header (time until the next token is available).

- Add `RateLimitedException` → 429 mapping in `GlobalExceptionHandler`.
- Invoke rate limiting in the relevant controller methods (or a `HandlerInterceptor`).
- Add a TODO comment: *"For multi-instance deployments, replace this in-memory map with a Redis-backed sliding window or API gateway rate limiting — requires ADR."*
- **Tests:** `RateLimiterTest` (unit — token bucket refills after window; per-user isolation; IP keying); `RateLimitIntegrationTest` (POST `send-otp` 6× from same IP → 6th returns 429 with `Retry-After`; PUT `/places/watch` 11× as same user → 11th returns 429).

**Implementation:** [`RateLimitProperties`](../server/src/main/java/odm/clarity/woleh/config/RateLimitProperties.java) (`@ConfigurationProperties(prefix = "woleh.ratelimit")`); [`PlaceListRateLimiter`](../server/src/main/java/odm/clarity/woleh/ratelimit/PlaceListRateLimiter.java) (`@Component`, `ConcurrentHashMap` fixed-window, `checkWatch` / `checkBroadcast`); [`RateLimitedException`](../server/src/main/java/odm/clarity/woleh/common/error/RateLimitedException.java) updated with `retryAfterSeconds` field; `GlobalExceptionHandler` updated to emit `Retry-After` header when `retryAfterSeconds > 0`; `PlaceListController` injects `PlaceListRateLimiter` and calls `checkWatch` / `checkBroadcast` on PUT handlers; `application.yml` gains `woleh.ratelimit.place-list.requests-per-minute: ${PLACE_LIST_RPM:10}`; `WolehApplication` registers `RateLimitProperties`; `UserPlaceList` constructor now sets `this.userId = user.getId()` to keep the read-only FK projection in sync for new in-memory entities. [`RateLimiterTest`](../server/src/test/java/odm/clarity/woleh/ratelimit/RateLimiterTest.java) — 7 unit tests; [`RateLimitIntegrationTest`](../server/src/test/java/odm/clarity/woleh/places/RateLimitIntegrationTest.java) — 5 integration tests (`@TestPropertySource` sets limit = 2).

**Done when:** rapid PUT of place lists from one user is rejected at 429 after the configured limit; a different user is unaffected; `Retry-After` header is present. ✅

---

### Step 2.2 — Spring Boot Actuator + Micrometer metrics (FR-O1) ✅

Add `spring-boot-starter-actuator` if not present. Configure in `application.yml`:

```yaml
management:
  server:
    port: 8081          # separate management port — not exposed publicly
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: always
```

Secure `/actuator/**` by restricting to the management port in `SecurityConfig` (the management port is separate from the main API port; add a note that the ops firewall should not expose port 8081 externally).

**Health:**
- `GET /actuator/health` — expose DB connectivity via Spring Boot's built-in `DataSourceHealthIndicator`; expose WebSocket subsystem via a custom `WsHealthIndicator implements HealthIndicator` that checks `WsSessionRegistry` is not null and the heartbeat scheduler has not faulted.

**Info:**
- `GET /actuator/info` — app name + version via Spring Boot's `build-info` plugin entry in `build.gradle`.

**Custom Micrometer metrics** (register in `MeterRegistry` injected into each component):

| Metric name | Type | Tags | Where registered |
|-------------|------|------|-----------------|
| `woleh.ws.sessions.active` | Gauge | — | `WsSessionRegistry` constructor via `Gauge.builder(...).register(registry)` |
| `woleh.place.list.put` | Counter | `list_type=watch\|broadcast` | `PlaceListService.putWatchList` / `putBroadcastList` on success |
| `woleh.match.evaluation` | Timer | — | `MatchingService` — wrap the intersection + dispatch block |
| `woleh.api.errors` | Counter | `status_class=4xx\|5xx` | `GlobalExceptionHandler` — increment on each mapped exception |

- **Tests:** `ActuatorHealthIntegrationTest` (`GET /actuator/health` with `webEnvironment = DEFINED_PORT, managementPort = ...` → 200 `{ "status": "UP" }`); metric registration smoke test (inject `MeterRegistry` bean, assert `woleh.ws.sessions.active` meter exists).

**Implementation:** `build.gradle` — `micrometer-registry-prometheus` dependency + `springBoot { buildInfo() }` (info endpoint); `application.yml` — `metrics,prometheus` added to exposure list, percentile histogram config for `http.server.requests`; [`WsHealthIndicator`](../server/src/main/java/odm/clarity/woleh/ws/WsHealthIndicator.java) (`@Component("ws")` — always UP, exposes `activeSessions` detail); `WsSessionRegistry` — `MeterRegistry` injected, `Gauge` for `woleh.ws.sessions.active`, `sessionCount()` added; `PlaceListService` — `MeterRegistry` injected, watch/broadcast `woleh.place.list.put` counters, incremented after successful save; `MatchingService` — `MeterRegistry` injected, `woleh.match.evaluation` Timer wraps intersection + dispatch blocks; `GlobalExceptionHandler` — `MeterRegistry` injected via constructor, `woleh.api.errors` 4xx/5xx counters pre-registered and incremented in each handler; `MatchingServiceTest` updated to pass `SimpleMeterRegistry`; `HealthIntegrationTest` gains `ws` component test; [`MetricsIntegrationTest`](../server/src/test/java/odm/clarity/woleh/api/MetricsIntegrationTest.java) — 6 smoke tests.

**Done when:** `GET /actuator/health` returns `UP` with `ws` component; the four custom meters are registered and can be queried via `GET /actuator/metrics/woleh.ws.sessions.active`. ✅

---

### Step 2.3 — Structured logging with correlation IDs (Architecture §5.7) ✅

Add `CorrelationIdFilter extends OncePerRequestFilter` registered at `HIGHEST_PRECEDENCE + 1`:
- Read `X-Request-Id` from the incoming request header; generate a `UUID.randomUUID()` if absent.
- `MDC.put("requestId", id)`.
- Echo the resolved ID as `X-Request-Id` on the response (via `HttpServletResponse.addHeader`).
- Clear MDC in `finally`.

Update `JwtAuthFilter`: after successful JWT validation, add `MDC.put("userId", String.valueOf(userId))`. Clear in `finally` as well.

Configure `src/main/resources/logback-spring.xml` (or update the existing one). Use a structured pattern that includes both context values:

```xml
<pattern>%d{yyyy-MM-dd'T'HH:mm:ss.SSSZ} %-5level [%X{requestId:-no-rid}] [userId:%X{userId:-anon}] %logger{36} - %msg%n</pattern>
```

For production, consider a JSON appender (Logstash/ECS layout) behind a Spring profile — add a stub `logback-spring.xml` profile `prod` with a note to wire to your log shipper.

Log updates:
- `TransitWebSocketHandler`: log connect/disconnect at INFO with `userId` (from session attributes) and `sessionId`.
- `MatchingService`: log each match dispatch at DEBUG (counterpartyIds + matchedNames count).
- `GlobalExceptionHandler`: log 5xx exceptions at ERROR with stack trace; 4xx at DEBUG (expected client errors).

**Tests:** `CorrelationIdFilterIntegrationTest` — fire any authenticated request; assert response contains `X-Request-Id` header; fire same request with a custom `X-Request-Id` → assert echoed back unchanged.

**Implementation:** [`CorrelationIdFilter`](../server/src/main/java/odm/clarity/woleh/security/CorrelationIdFilter.java) — `@Component @Order(HIGHEST_PRECEDENCE + 1)`, reads/generates `X-Request-Id`, `MDC.put("requestId", ...)`, echoes header, clears in `finally`; `JwtAuthenticationFilter` — `MDC.put("userId", ...)` after successful JWT parse, clears in `finally`; [`logback-spring.xml`](../server/src/main/resources/logback-spring.xml) created with `[%X{requestId:-no-rid}] [userId:%X{userId:-anon}]` pattern; `!prod` / `prod` Spring profiles (prod stub awaiting logstash-logback-encoder); `TransitWebSocketHandler` connect/disconnect upgraded to INFO; `GlobalExceptionHandler` gets `Logger` — 5xx at ERROR with stack trace, 4xx at DEBUG; [`CorrelationIdFilterIntegrationTest`](../server/src/test/java/odm/clarity/woleh/api/CorrelationIdFilterIntegrationTest.java) — 2 tests (auto-generated UUID, custom echoed back).

**Done when:** every log line for a request carries `requestId`; authenticated requests also carry `userId`; responses echo `X-Request-Id`. ✅

---

### Step 2.4 — JWT token refresh (FR-A2) ✅

FR-A2 ("token refresh or re-auth policy documented and implemented") has been deferred since Phase 0. Implement refresh tokens:

**DB:** Add `refresh_tokens` table via Flyway migration:
- `id` (PK), `user_id` (FK → `users`), `token_hash` (varchar — store `SHA-256` hex of the raw token, never the raw token itself), `expires_at`, `revoked` (boolean, default false), `created_at`.
- Index on `token_hash`; unique constraint on `token_hash`.

**New endpoint:** `POST /api/v1/auth/refresh`
- Body: `{ "refreshToken": "<opaque string>" }`.
- Hash the incoming token; look up `refresh_tokens` by hash; reject if not found, revoked, or expired → `401` with `code: "INVALID_REFRESH_TOKEN"`.
- Rotate: mark old token as `revoked = true`; issue new access token (short TTL — e.g. 15 min) + new refresh token (longer TTL — e.g. 30 days); store new refresh token hash in DB.
- Return: `{ "accessToken": "...", "refreshToken": "...", "expiresIn": 900 }`.

**Logout update:** `POST /api/v1/auth/logout` — revoke the user's current refresh token (if provided in body or identified from the access token's `userId`). Clear all refresh tokens for the user if paranoid logout is desired.

**Issuance update:** `POST /api/v1/auth/verify-otp` — in addition to `accessToken`, return a `refreshToken` (and `expiresIn`). Add `RefreshToken` to the verify-OTP response DTO.

**`JwtService`:** add `generateRefreshToken()` (returns a cryptographically random 32-byte hex string) and `hashToken(String raw): String` (SHA-256 hex).

**Tests:** `RefreshTokenIntegrationTest` — verify OTP → get refresh token; use refresh token → get new access + refresh token pair; old refresh token rejected after rotation; revoked token rejected; expired token rejected.

**Implementation:** `V6__refresh_tokens.sql` — `refresh_tokens` table (SHA-256 hash col, `ON DELETE CASCADE`); [`RefreshToken`](../server/src/main/java/odm/clarity/woleh/model/RefreshToken.java) entity + [`RefreshTokenRepository`](../server/src/main/java/odm/clarity/woleh/repository/RefreshTokenRepository.java); `JwtService` — `generateRefreshToken()` (32-byte `SecureRandom` hex) + `hashToken()` (SHA-256); `WolehJwtProperties` — `refreshTokenTtl` (default 30 days); [`RefreshTokenService`](../server/src/main/java/odm/clarity/woleh/auth/service/RefreshTokenService.java) — `issue()`, `rotate()` (marks old revoked, issues new pair), `revokeByRawToken()` (paranoid logout — deletes all tokens for user); `InvalidRefreshTokenException` + `GlobalExceptionHandler` → 401 `INVALID_REFRESH_TOKEN`; `VerifyOtpResponse` — `refreshToken` field added; `AuthController` — `POST /auth/refresh` + `POST /auth/logout` endpoints, `verify-otp` now issues refresh token; `SecurityConfig` permits both new endpoints; `application.yml` + `WolehJwtProperties` wired; `RefreshTokenIntegrationTest` (6 tests); `VerifyOtpIntegrationTest` asserts `refreshToken` present; 215 server tests green.

**Done when:** a client can exchange an expired access token using a refresh token without re-entering OTP; logout invalidates the refresh token. ✅

---

### Step 2.5 — API tests and Phase 3 artifacts ✅

- **`server/api-tests/phase3.http`**: rate limit demo (11× PUT watch → 429 with `Retry-After`), health check (`GET /actuator/health`), correlation ID echo (`GET /api/v1/me` → inspect `X-Request-Id` response header), refresh token flow (verify OTP → refresh → new tokens).
- **`http-client.env.json`**: add `managementBaseUrl` (e.g. `http://localhost:8081`).

**Implementation:** [`phase3.http`](../server/api-tests/phase3.http) — 6 sections: auth, 11-request rate-limit demo (10 succeed, 11th → 429 + Retry-After), Actuator health/info/metrics/prometheus, correlation-ID echo (custom + auto-generated), refresh token rotation + rejection of old token, logout + post-logout rejection; [`http-client.env.json`](../server/api-tests/http-client.env.json) — `managementBaseUrl` added to `dev` and `staging` environments.

**Done when:** CI is green; `.http` file documents Phase 3 server flows for manual QA. ✅

---

## 3. Mobile (Flutter)

### Step 3.1 — Refresh token integration (FR-A2, client side) ✅

Wire the new refresh token flow into the mobile auth layer:

- **`AuthRepository`**: `verifyOtp` now returns `accessToken` + `refreshToken` + `expiresIn`; store both in secure storage (`flutter_secure_storage`) — access token (or its expiry) and refresh token.
- **`ApiClient` interceptor** (`AppErrorInterceptor` or a new `TokenRefreshInterceptor`): on `401` response, automatically call `POST /api/v1/auth/refresh` with the stored refresh token; on success, retry the original request with the new access token; on failure (refresh rejected) → clear stored tokens → emit sign-out via `authStateProvider`.
- **`WsClient`**: already reads the current access token from `authStateProvider`; no change needed beyond ensuring reconnect after token refresh reuses the new token.
- **`AuthRepository.logout`**: call `POST /api/v1/auth/logout` (send refresh token); clear both tokens from secure storage regardless of server response.

**Tests:** `TokenRefreshInterceptorTest` (unit — mock HTTP: first request 401, refresh 200, retry 200 → original response returned; refresh 401 → sign-out emitted; mock `flutter_secure_storage`).

**Done when:** a user with an expired access token has requests transparently retried after background refresh; a failed refresh signs the user out cleanly. ✅

**Implementation:** 7 files changed — `auth_token_storage.dart` (+ `readRefreshToken` / `writeRefreshToken` / `deleteRefreshToken`); `auth_state.dart` (`setTokens()`, `signOut()` clears both tokens); `auth_dto.dart` (`refreshToken` field on `VerifyOtpResponse`, new `RefreshResponse` DTO); `auth_repository.dart` (`refresh()` + `logout()`); `api_client.dart` (new `TokenRefreshInterceptor` class, separate `refreshDio` to avoid recursion, `AppErrorInterceptor` changed from `reject()` → `next()` so `TokenRefreshInterceptor` runs after it in Dio 5's forward error chain); `otp_screen.dart` (stores both tokens on verify). 4 unit tests in `test/core/token_refresh_interceptor_test.dart`. 155 Flutter tests passing.

---

### Step 3.2 — Offline read-only cache (PRD §13.7) ✅

Cache last-known profile and place lists for display when the device is offline. Mutations remain disabled offline.

**Dependencies:** add `shared_preferences` (or `hive_flutter` if already present) to `pubspec.yaml`.

**`MeRepository`** (this codebase’s equivalent of a profile repository — `GET /api/v1/me`): after a successful response, serialize the full [`MeResponse`](../mobile/lib/features/me/data/me_dto.dart) to JSON and persist via `SharedPreferences` under key `cache.profile`. On `DioException` where connectivity is absent (`DioExceptionType.connectionError` / `DioExceptionType.unknown` with no response; see [`isOfflineDioException`](../mobile/lib/core/offline_dio.dart)), return the cached `MeResponse` (same [`me_dto.dart`](../mobile/lib/features/me/data/me_dto.dart) types) wrapped in `MeLoadSnapshot` with `fromCache: true` if available; throw [`OfflineError`](../mobile/lib/core/app_error.dart) if no cache exists.

**`PlaceListRepository`**: same pattern for watch list (`cache.places.watch`) and broadcast list (`cache.places.broadcast`); successful GET/PUT updates the corresponding cache; getters return [`PlaceListSnapshot`](../mobile/lib/features/places/data/place_list_repository.dart) (`names` + `fromCache`).

**UI indicators:**
- [`OfflineError`](../mobile/lib/core/app_error.dart) in the `AppError` hierarchy; home error state shows its message when `/me` fails with no cache.
- When data was **loaded from cache** (`fromCache` / `readOnlyOffline`), show a non-intrusive **"Showing saved data"** chip ([`ShowingSavedDataChip`](../mobile/lib/shared/offline_read_only_hint.dart)). Disable Save / add / remove / reorder with tooltip **`Offline — changes unavailable`** ([`kOfflineMutationsTooltip`](../mobile/lib/shared/offline_read_only_hint.dart)).
- **`HomeScreen`**: chip at top of profile list when profile snapshot is from cache.

**Tests:** [`me_repository_cache_test.dart`](../mobile/test/features/me/me_repository_cache_test.dart) + [`place_list_repository_cache_test.dart`](../mobile/test/features/places/place_list_repository_cache_test.dart) (mock `Dio` / adapter — connection error → cached value; no cache + offline → `OfflineError`; optional `unknown` + no response path).

**Done when:** a user who has previously loaded their watch list can open the app with no connectivity and see their last-saved list (read-only); Save button is disabled with a clear message. ✅

**Implementation:** `shared_preferences` in [`pubspec.yaml`](../mobile/pubspec.yaml); [`shared_preferences_provider.dart`](../mobile/lib/core/shared_preferences_provider.dart) overridden in async [`main.dart`](../mobile/lib/main.dart) after `SharedPreferences.getInstance()`; [`offline_dio.dart`](../mobile/lib/core/offline_dio.dart); `MeProfile` / `MeLimits` / `MeSubscription` / `MeResponse` — `toJson()` in [`me_dto.dart`](../mobile/lib/features/me/data/me_dto.dart) + `MeLoadSnapshot`; [`me_repository.dart`](../mobile/lib/features/me/data/me_repository.dart) (`getMe()` → `MeLoadSnapshot`); [`place_list_repository.dart`](../mobile/lib/features/places/data/place_list_repository.dart); [`me_notifier.dart`](../mobile/lib/features/me/presentation/me_notifier.dart) → `AsyncValue<MeLoadSnapshot?>`; [`router.dart`](../mobile/lib/app/router.dart), [`permission_provider.dart`](../mobile/lib/core/permission_provider.dart), [`plans_screen.dart`](../mobile/lib/features/subscription/presentation/plans_screen.dart), [`checkout_notifier.dart`](../mobile/lib/features/subscription/presentation/checkout_notifier.dart), [`profile_edit_screen.dart`](../mobile/lib/features/me/presentation/profile_edit_screen.dart) — consumers use `snapshot.me`; [`home_screen.dart`](../mobile/lib/features/home/presentation/home_screen.dart); [`watch_notifier.dart`](../mobile/lib/features/places/presentation/watch_notifier.dart) / [`broadcast_notifier.dart`](../mobile/lib/features/places/presentation/broadcast_notifier.dart) (`readOnlyOffline`, `OfflineError` on load); [`watch_screen.dart`](../mobile/lib/features/places/presentation/watch_screen.dart) / [`broadcast_screen.dart`](../mobile/lib/features/places/presentation/broadcast_screen.dart). 3 + 4 unit tests in cache test files; [`place_list_repository_test.dart`](../mobile/test/features/places/place_list_repository_test.dart) updated for `PlaceListSnapshot`; router/widget/subscription test stubs updated for `MeLoadSnapshot`. **162** Flutter tests green.

---

### Step 3.3 — WebSocket degraded state indicator (NFR-2) ✅

Surface WS connectivity state so users know when live updates are paused.

**`WsClient`:** extend the notifier to track and expose connection state. Add a `WsConnectionState` enum:

```dart
enum WsConnectionState { connecting, connected, reconnecting, disconnected }
```

Expose `connectionState` as a `ValueNotifier<WsConnectionState>` or as part of the provider state. Update state transitions:
- `connect()` called → `connecting`.
- First message received (including heartbeat) → `connected`; reset backoff counter.
- `onDone` / `onError` → `reconnecting` (with attempt count); after max attempts (e.g. 10) → `disconnected`.
- `disconnect()` called explicitly → `disconnected`.

**UI:** add a `WsStatusBanner` widget (`mobile/lib/shared/ws_status_banner.dart`) — a slim `MaterialBanner` or `AnimatedContainer` that:
- Shows `"Live updates unavailable — reconnecting…"` when `reconnecting`.
- Shows `"Live updates offline"` with a manual retry button when `disconnected`.
- Is invisible (zero height) when `connected` or `connecting`.

Insert `WsStatusBanner` at the top of the `HomeScreen`, `WatchScreen`, and `BroadcastScreen` body (above the existing content, inside the `Column`).

**Tests:** `WsStatusBannerTest` (widget tests — `reconnecting` state → banner text visible; `connected` state → banner absent; `disconnected` → offline text + retry button visible).

**Done when:** a simulated WS drop causes the banner to appear on the home screen; reconnection hides it. ✅

**Implementation:** [`WsConnectionState`](../mobile/lib/core/ws_client.dart) + `ValueNotifier<WsConnectionState> connectionState` on [`WsClient`](../mobile/lib/core/ws_client.dart); `_kMaxReconnectCycles = 10` (after 11 consecutive connection losses without receiving a frame, state → `disconnected`); `retryConnection()` resets backoff and calls `connect()`; [`WsStatusBanner`](../mobile/lib/shared/ws_status_banner.dart) + testable [`WsStatusBannerCore`](../mobile/lib/shared/ws_status_banner.dart); banner wired in [`home_screen.dart`](../mobile/lib/features/home/presentation/home_screen.dart), [`watch_screen.dart`](../mobile/lib/features/places/presentation/watch_screen.dart), [`broadcast_screen.dart`](../mobile/lib/features/places/presentation/broadcast_screen.dart) (`Column` + `Expanded`). Widget tests in [`ws_status_banner_test.dart`](../mobile/test/shared/ws_status_banner_test.dart); connection-state coverage in [`ws_client_test.dart`](../mobile/test/core/ws_client_test.dart). **170** Flutter tests green.

---

### Step 3.4 — Push notifications for match events and subscription expiry (FR-N1 — P2) ✅

Feature-flagged off by default (`woleh.push.enabled: false` in `application.yml`; `kPushEnabled` / `--dart-define=WOLEH_PUSH_ENABLED` in Flutter). End-to-end wiring is in place; production pushes require real FCM credentials.

**Mobile:**
- Add `firebase_messaging` and `firebase_core` to `pubspec.yaml`; placeholder [`google-services.json`](../mobile/android/app/google-services.json) and [`GoogleService-Info.plist`](../mobile/ios/Runner/GoogleService-Info.plist) (replace via Firebase console / `flutterfire configure`).
- [`PushBootstrap`](../mobile/lib/core/push_bootstrap.dart) + [`kPushEnabled`](../mobile/lib/core/push_bootstrap.dart): when enabled, `Firebase.initializeApp()` after first frame; permission prompt once (`SharedPreferences` gate); on grant, `getToken()` + `MeRepository.registerDeviceToken`; `onTokenRefresh` re-posts; foreground `FirebaseMessaging.onMessage` → floating `SnackBar` via [`rootScaffoldMessengerKey`](../mobile/lib/main.dart).
- Sign-out: [`pushBeforeSignOutProvider`](../mobile/lib/core/push_hook.dart) + [`unregisterPushDevices`](../mobile/lib/core/push_bootstrap.dart) → `DELETE /api/v1/me/device-token` with last stored token (best-effort before tokens are cleared in [`AuthState.signOut`](../mobile/lib/core/auth_state.dart)).

**Server:**
- **DB:** [`V7__device_tokens.sql`](../server/src/main/resources/db/migration/V7__device_tokens.sql); JPA [`DeviceToken`](../server/src/main/java/odm/clarity/woleh/model/DeviceToken.java) + [`DeviceTokenRepository`](../server/src/main/java/odm/clarity/woleh/repository/DeviceTokenRepository.java); [`DeviceTokenService`](../server/src/main/java/odm/clarity/woleh/push/DeviceTokenService.java) upsert/delete.
- [`DeviceTokenController`](../server/src/main/java/odm/clarity/woleh/api/DeviceTokenController.java) `POST`/`DELETE` `/api/v1/me/device-token`; [`EntitlementService`](../server/src/main/java/odm/clarity/woleh/subscription/EntitlementService.java) enforces `woleh.account.profile`; invalid platform → [`BadRequestException`](../server/src/main/java/odm/clarity/woleh/common/error/BadRequestException.java).
- [`FcmService`](../server/src/main/java/odm/clarity/woleh/push/FcmService.java): [`StubFcmService`](../server/src/main/java/odm/clarity/woleh/push/StubFcmService.java) (`@ConditionalOnMissingBean(RealFcmService.class)`); [`RealFcmService`](../server/src/main/java/odm/clarity/woleh/push/RealFcmService.java) when `woleh.push.enabled=true` (FCM HTTP v1 via Spring `RestClient` + Google service-account JSON path).
- [`MatchingService`](../server/src/main/java/odm/clarity/woleh/places/MatchingService.java): after each `sendMatchEvent`, if [`WsSessionRegistry.hasOpenSession`](../server/src/main/java/odm/clarity/woleh/ws/WsSessionRegistry.java) is false → push match copy; avoids duplicate when the user already has a live WS session.
- [`SubscriptionExpiryNotifier`](../server/src/main/java/odm/clarity/woleh/subscription/SubscriptionExpiryNotifier.java): daily 08:00 UTC; [`SubscriptionRepository.findActiveExpiringBetween`](../server/src/main/java/odm/clarity/woleh/repository/SubscriptionRepository.java) for `ACTIVE` subs with `current_period_end` in `(now, now+24h]`; one notification per user per run.

- `test/features/me/me_repository_device_token_test.dart` — step 3.4 (device-token API)

**Done when (feature flag off):** token registration + deletion endpoints work; `StubFcmService` logs notifications during integration tests without sending real pushes. ✅ **Done when (feature flag on):** a real FCM token receives a notification when a match event fires for an offline user.

**Implementation:** `woleh.push` + `spring.task.scheduling.enabled=false` in server test [`application.properties`](../server/src/test/resources/application.properties); [`@EnableScheduling`](../server/src/main/java/odm/clarity/woleh/WolehApplication.java); Android `com.google.gms.google-services`; **175** Flutter tests green; **220** server tests green.

---

### Step 3.5 — Tests and Phase 3 QA artifacts

All test files created incrementally in steps 3.1–3.4. This step validates coverage and adds any missing edge cases:

- `test/core/token_refresh_interceptor_test.dart` — step 3.1 ✓
- `test/features/me/me_repository_cache_test.dart` — step 3.2 ✓
- `test/features/places/place_list_repository_cache_test.dart` — step 3.2 ✓
- `test/shared/ws_status_banner_test.dart` — step 3.3 ✓
- `test/core/ws_client_test.dart` — step 3.3 ✓ (connection state; includes reconnect backoff tests)
- `test/core/push_service_test.dart` — step 3.4 ✓ (`kPushEnabled` default)
- `test/features/me/me_repository_device_token_test.dart` — step 3.4 (device-token API)

Confirm CI is green. Update `server/api-tests/phase3.http` (step 2.5) if any endpoint shapes changed during mobile implementation.

**Done when:** CI is green; all Phase 3 screens and new core utilities have test coverage.

---

## 4. Docs and ops

### Step 4.1 — SLO baseline (NFR-1 exit criterion)

Create `docs/runbooks/SLO_BASELINE.md`:

- Define p95 latency targets per endpoint group:

| Endpoint group | p95 target | Measurement source |
|----------------|------------|-------------------|
| Auth (send-otp, verify-otp) | < 500 ms | `woleh.match.evaluation` timer + Spring Boot default HTTP timer |
| Place list reads (`GET /me/places/*`) | < 200 ms | Spring Boot HTTP server request metrics |
| Place list writes (`PUT /me/places/*`) + match dispatch | < 500 ms | Spring Boot HTTP server request metrics |
| WebSocket handshake | < 300 ms | Actuator + WS handler logs |

- Document how to query baselines: `GET /actuator/metrics/http.server.requests?tag=uri:/api/v1/me/places/watch` + percentile histogram config in `application.yml`.
- Document alert thresholds: if p95 breaches target for 5 consecutive minutes → page on-call.
- Note: percentile histograms require `management.metrics.distribution.percentiles-histogram.http.server.requests=true` in `application.yml`.

---

### Step 4.2 — Incident runbooks

Create `docs/runbooks/INCIDENT_RESPONSE.md` covering the most likely failure scenarios:

1. **WS session leak** — symptoms: `woleh.ws.sessions.active` gauge grows without bound; mitigation: restart heartbeat scheduler clears dead sessions; check `TransitWebSocketHandler` logs for disconnect events not firing.
2. **Match dispatch latency spike** — symptoms: `woleh.match.evaluation` timer p95 rises; likely cause: growing number of active place lists (O(n) in-memory scan); mitigation: restrict broadcast/watch lists; longer-term: indexed PostgreSQL `jsonb` query (ADR needed).
3. **Rate limit false positives** — symptoms: legitimate users hitting 429; mitigation: increase `woleh.ratelimit.place-list.requests-per-minute` via config restart; confirm key is per-user, not global.
4. **DB migration failure** — steps: check Flyway migration log (`flyway_schema_history`); rollback procedure (restore from pre-migration snapshot; re-run with fix); document that `normalized_names` re-normalization is required if `PlaceNameNormalizer` algorithm changes (see `V5` migration comment).
5. **Subscription grace period edge case** — if a user's permissions seem wrong, check `subscriptions.grace_period_end` vs current timestamp; `EntitlementService` log lines (DEBUG) show resolved tier.
6. **Push token staleness** — if push notifications stop for a user, check `device_tokens.updated_at`; FCM tokens rotate; the client refreshes the token on app launch via `PushService`.

---

## 5. Definition of done (Phase 3)

- [ ] `PUT /api/v1/me/places/watch` and `PUT /api/v1/me/places/broadcast` return 429 after exceeding per-user rate limit; `Retry-After` header present. *(Step 2.1)*
- [ ] `POST /api/v1/auth/send-otp` returns 429 after exceeding per-IP OTP limit. *(Step 2.1)*
- [ ] `GET /actuator/health` returns `{ "status": "UP" }` with DB component; accessible on management port only. *(Step 2.2)*
- [ ] Four custom Micrometer meters registered: WS sessions gauge, place list put counter, match evaluation timer, API error counter. *(Step 2.2)*
- [ ] Every request log line carries `requestId`; authenticated requests carry `userId`; every response echoes `X-Request-Id`. *(Step 2.3)*
- [ ] `POST /api/v1/auth/refresh` issues new access + refresh token pair; old token rejected after rotation. *(Step 2.4)*
- [ ] `POST /api/v1/auth/logout` revokes the refresh token. *(Step 2.4)*
- [ ] Mobile: expired access token transparently refreshes in the background; failed refresh signs user out. *(Step 3.1)*
- [x] Mobile: last-known profile and place lists displayed when offline; Save/edit actions disabled. *(Step 3.2)*
- [x] Mobile: WS degraded state banner appears on disconnect/reconnect; disappears on reconnect. *(Step 3.3)*
- [x] Push notification device token registration + deletion endpoints functional; `StubFcmService` logs match/expiry events in tests without sending real pushes. *(Step 3.4)*
- [ ] CI passes: server + mobile tests green. *(Step 3.5)*
- [ ] `docs/runbooks/SLO_BASELINE.md` written with p95 targets and query instructions. *(Step 4.1)*
- [ ] `docs/runbooks/INCIDENT_RESPONSE.md` written with at least 6 failure scenarios. *(Step 4.2)*

---

## 6. Document history

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2026-04-10 | Initial Phase 3 codable breakdown |
| 0.2 | 2026-04-10 | Step 2.1 implemented: `RateLimitProperties` + `PlaceListRateLimiter` (fixed-window `ConcurrentHashMap`); `RateLimitedException` gains `retryAfterSeconds`; `GlobalExceptionHandler` emits `Retry-After` header; `PlaceListController` calls rate limiter on PUTs; `application.yml` + `WolehApplication` wired; `UserPlaceList` constructor populates read-only `userId` projection; `RateLimiterTest` (7 unit) + `RateLimitIntegrationTest` (5 integration); 199 server tests green |
| 0.3 | 2026-04-10 | Step 2.2 implemented: `micrometer-registry-prometheus` + `buildInfo()`; `metrics` + `prometheus` exposure + percentile histogram config; `WsHealthIndicator` (`ws` component, `activeSessions` detail); `WsSessionRegistry` Gauge + `sessionCount()`; `PlaceListService` watch/broadcast PUT counters; `MatchingService` evaluation Timer; `GlobalExceptionHandler` 4xx/5xx error counters; `MatchingServiceTest` updated; `HealthIntegrationTest` + `MetricsIntegrationTest` (6 new tests); 206 server tests green |
| 0.4 | 2026-04-10 | Step 2.3 implemented: `CorrelationIdFilter` (`HIGHEST_PRECEDENCE + 1`, MDC `requestId`, echo `X-Request-Id`); `JwtAuthenticationFilter` MDC `userId` + `finally` clear; `logback-spring.xml` with correlation-ID pattern + `prod` profile stub; `TransitWebSocketHandler` connect/disconnect to INFO; `GlobalExceptionHandler` logging (5xx ERROR with stack trace, 4xx DEBUG); `CorrelationIdFilterIntegrationTest` (2 tests); 208 server tests green |
| 0.5 | 2026-04-10 | Step 2.4 implemented: `V6__refresh_tokens.sql`; `RefreshToken` entity + `RefreshTokenRepository`; `JwtService` — `generateRefreshToken()` + `hashToken()`; `WolehJwtProperties` — `refreshTokenTtl`; `RefreshTokenService` — issue/rotate/revokeByRawToken; `InvalidRefreshTokenException` → 401; `VerifyOtpResponse` + `AuthController` updated; `POST /auth/refresh` + `POST /auth/logout` endpoints; `RefreshTokenIntegrationTest` (6 tests); 215 server tests green |
| 0.6 | 2026-04-10 | Step 2.5 implemented: `phase3.http` (6 sections: auth, rate-limit demo, Actuator, correlation IDs, refresh token rotation, logout); `http-client.env.json` — `managementBaseUrl` added; 215 server tests green |
| 0.7 | 2026-04-10 | Step 3.1 implemented: `AuthTokenStorage` + refresh token storage; `AuthState.setTokens()` + `signOut()` clears both tokens; `VerifyOtpResponse.refreshToken` + `RefreshResponse` DTO; `AuthRepository.refresh()` + `logout()`; `TokenRefreshInterceptor` (401 → silent refresh → retry; failed refresh → signOut); `AppErrorInterceptor` changed `reject()` → `next()` for Dio 5 forward error chain; `otp_screen.dart` stores both tokens; `token_refresh_interceptor_test.dart` (4 unit tests); 155 Flutter tests green |
| 0.8 | 2026-04-10 | Step 3.2 implemented: `shared_preferences` + `shared_preferences_provider` (override in `main.dart`); `offline_dio.dart`; `OfflineError`; `MeResponse`/`MeProfile`/limits/subscription `toJson()` + `MeLoadSnapshot`; `MeRepository` + `PlaceListRepository` offline cache keys (`cache.profile`, `cache.places.watch`, `cache.places.broadcast`) + `PlaceListSnapshot`; `meNotifierProvider` → `MeLoadSnapshot?`; home/watch/broadcast UI (`ShowingSavedDataChip`, read-only offline); `me_repository_cache_test` (3) + `place_list_repository_cache_test` (4); 162 Flutter tests green |
| 0.9 | 2026-04-10 | Step 3.3 implemented: `WsConnectionState` + `WsClient.connectionState` `ValueNotifier`; reconnect cap `_kMaxReconnectCycles`; `retryConnection()`; `WsStatusBanner` / `WsStatusBannerCore`; home/watch/broadcast `Column` layout; `ws_status_banner_test.dart` (4 widget tests) + `ws_client_test` connection-state tests; 170 Flutter tests green |
- `test/features/me/me_repository_device_token_test.dart` — step 3.4 (device-token API)
