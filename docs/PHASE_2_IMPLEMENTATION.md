# Phase 2 — Implementation breakdown (codable steps)

This document turns [PRD.md](./PRD.md) §10 **Phase 2 — Core transit journey** into ordered, implementable work. **Exit criterion:** a rider/operator place-name flow works in staging — a user with `woleh.place.watch` sets a watch list, a user with `woleh.place.broadcast` sets a broadcast list, the server matches by normalized name intersection, and both parties receive a real-time `match` event over WebSocket.

**References:** [ARCHITECTURE.md](./ARCHITECTURE.md), [API_CONTRACT.md](./API_CONTRACT.md) §6.7–§6.10 and §8, [PLACE_NAMES.md](./PLACE_NAMES.md), [PRD.md](./PRD.md) §6.3, §13.2, [ADR 0001](./adr/0001-websocket-authentication.md) (WS auth), [Phase 1 implementation](./PHASE_1_IMPLEMENTATION.md).

### Locked identifiers (carry-over from Phase 0–1)

| Artifact | Value |
|----------|--------|
| **Server base package** | `odm.clarity.woleh` |
| **Flutter package** | `odm_clarity_woleh_mobile` |
| **Riverpod** | Codegen on — `@riverpod` / `@Riverpod` + `*.g.dart` |
| **WS path** | `/ws/v1/transit` |
| **WS auth** | `?access_token=<jwt>` query param ([ADR 0001](./adr/0001-websocket-authentication.md)) |

---

## 1. Scope

| In scope (Phase 2) | Deferred |
|--------------------|----------|
| `PlaceNameNormalizer` utility (server) + test vectors | Fuzzy / alias matching (§13.8, out of scope) |
| DB schema: `user_place_lists` table | Multi-language normalization edge cases |
| `GET` + `PUT /api/v1/me/places/watch` (replace list; limit + dedupe enforcement) | Background GPS / location tracking (FR-L1–FR-L2 are P2 but depend on a separate ADR) |
| `GET` + `PUT /api/v1/me/places/broadcast` (ordered; limit + dedupe enforcement) | Push notifications for match events (FR-N1 — Phase 3) |
| `MatchingService` (server): find intersecting broadcast/watch lists across users | Rate limiting beyond OTP (Phase 3) |
| WebSocket endpoint `/ws/v1/transit` — JWT auth, `{ type, data }` envelope, 15 s heartbeat | Admin / support tools (FR-O2) |
| Realtime match dispatch: push `match` event when a list PUT creates new intersections | Refresh tokens / re-auth policy |
| Mobile: `normalizePlaceName` Dart utility + shared test vectors | STOMP or pub-sub broker (raw WS sufficient for v1) |
| Mobile: Watch screen (add/remove names, preview, PUT list) | |
| Mobile: Broadcast screen (ordered add/reorder/remove, PUT list) | |
| Mobile: WebSocket client (connect, reconnect with backoff, heartbeat, unknown-type ignore) | |
| Mobile: Incoming `match` event — banner / notification on applicable screen | |
| `.http` collection updated for Phase 2 flows | |

**Matching scope for v1:** On every `PUT` to either place list, the server queries all active lists of the complementary type and pushes `match` events in-band. No separate "start" or "stop" command beyond sending an empty list (clearing it). This is O(n active lists) — acceptable for staging scale; a Phase 3 ADR may add indexed matching if needed.

---

## 2. Server (Spring Boot)

### Step 2.1 — Place-name normalization utility ✅

Implement `PlaceNameNormalizer` per [PLACE_NAMES.md](./PLACE_NAMES.md) §1:

1. **Trim** — strip leading/trailing Unicode whitespace.
2. **NFC** — apply `java.text.Normalizer` with `Normalizer.Form.NFC`.
3. **Case fold** — `String.toLowerCase(Locale.ROOT)` for ASCII-dominated input (sufficient for v1 Ghana-English; document the choice; swap for ICU if test vectors fail).
4. **Collapse internal whitespace** — replace every maximal run of `\s+` with a single ASCII space; trim again.

- Expose as a `@Component` with a single public method `normalize(String input): String`.
- Implement validation helper `validatePlaceName(String raw)` used by both watch and broadcast write paths: rejects empty-after-trim; rejects over-200 Unicode scalar values.
- Add unit tests **`PlaceNameNormalizerTest`** covering the three canonical test vectors from [PLACE_NAMES.md](./PLACE_NAMES.md) §5 plus edge cases (null-like empty, 201-char name, internal tab, mixed case).

**Implementation:** [`PlaceNameNormalizer`](../server/src/main/java/odm/clarity/woleh/places/util/PlaceNameNormalizer.java); [`PlaceNameValidationException`](../server/src/main/java/odm/clarity/woleh/common/error/PlaceNameValidationException.java) (registered → 400 in `GlobalExceptionHandler`); [`PlaceNameNormalizerTest`](../server/src/test/java/odm/clarity/woleh/places/util/PlaceNameNormalizerTest.java) — 17 tests (3 spec vectors + 14 edge cases).

**Done when:** all test vectors in [PLACE_NAMES.md](./PLACE_NAMES.md) §5 pass; `normalize` is idempotent (calling it twice produces the same result). ✅

---

### Step 2.2 — Place-list DB schema

Add one table via Flyway migration:

- **`user_place_lists`**: `id` (PK), `user_id` (FK → `users`, non-null), `list_type` (varchar: `watch` | `broadcast`), `display_names` (JSON array of strings — user-entered display form), `normalized_names` (JSON array of strings — normalized form, stored for efficient matching queries), `updated_at`.
- Unique constraint on `(user_id, list_type)` — at most one watch row and one broadcast row per user.

Store both display and normalized forms: display form is returned to the client; normalized form is used for matching queries without re-normalizing at read time. If the normalization algorithm changes, a migration must re-normalize stored values (document this risk in the migration comment).

**Implementation:** Flyway **`V5__user_place_lists.sql`**; JPA entity `UserPlaceList`; Spring Data repository `UserPlaceListRepository` (with `findByUserIdAndListType`, `findAllByListType`); enum `PlaceListType` (`WATCH`, `BROADCAST`); `StringListConverter` (reuse or extend the one from Phase 1 for JSON ↔ `List<String>`).

**Done when:** migrations apply cleanly; a `UserPlaceListRepository` round-trip test verifies both list types save and reload correctly.

---

### Step 2.3 — `GET` + `PUT /api/v1/me/places/watch`

Implement per [API_CONTRACT.md](./API_CONTRACT.md) §6.7–§6.8:

- **`GET /api/v1/me/places/watch`**: requires `woleh.place.watch`; return `{ "names": [...] }` from `display_names` (insertion order preserved); return empty list if no row exists.
- **`PUT /api/v1/me/places/watch`**: requires `woleh.place.watch`; body `{ "names": [...] }`.
  - Validate each name with `PlaceNameNormalizer.validatePlaceName`.
  - Compute normalized forms; dedupe by normalized equality (keep first occurrence of each normalized form, preserving display name of the first occurrence).
  - Enforce `limits.placeWatchMax` after dedupe → **403** with `code: "OVER_LIMIT"` if exceeded.
  - Upsert the `user_place_lists` row (create if absent, replace lists if present).
  - After a successful save, call `MatchingService.dispatchWatchMatches(userId, normalizedNames)` (step 2.5) to push real-time events.
  - Return the saved list: `{ "names": [...] }` (display form, deduped).

**Implementation:** `PlaceListController` at `/api/v1/me/places`; `PlaceNamesRequest` / `PlaceNamesResponse` DTOs; `PlaceListService.getWatchList` / `putWatchList`; `PlaceLimitExceededException` → 403 in `GlobalExceptionHandler`; `WatchListIntegrationTest` (401, 403 missing permission, 400 empty name, 400 over-length, 403 over-limit, 200 save + retrieve, dedupe behavior).

**Done when:** a paid user can PUT and GET a watch list; free user with capped list gets 403 on exceeding 5 names; empty list PUT clears it.

---

### Step 2.4 — `GET` + `PUT /api/v1/me/places/broadcast`

Implement per [API_CONTRACT.md](./API_CONTRACT.md) §6.9–§6.10 — mirrors step 2.3 but for broadcast:

- **`GET /api/v1/me/places/broadcast`**: requires `woleh.place.broadcast`; return `{ "names": [...] }` in stored order (sequence is significant); **403** for users missing the permission.
- **`PUT /api/v1/me/places/broadcast`**: requires `woleh.place.broadcast`.
  - Same validation as watch: per-name length, non-empty after trim.
  - Dedupe by normalized equality (PRD §13.2: "dedupe on save recommended"); for broadcast, if duplicate normalized names appear and product policy is **400**, return `400` with a clear message. Default: reject with 400 per API contract §6.10 note.
  - Enforce `limits.placeBroadcastMax` after dedupe.
  - Upsert the broadcast row; order is preserved (stored as JSON array).
  - After save, call `MatchingService.dispatchBroadcastMatches(userId, normalizedNames)` (step 2.5).
  - Return `{ "names": [...] }` (display form, stored order).

**Implementation:** `PlaceListService.getBroadcastList` / `putBroadcastList`; `PlaceListController` updated; `BroadcastListIntegrationTest` (401, 403 missing permission, 400 duplicate normalized names, 400 over-limit, 200 save + retrieve, order preserved).

**Done when:** a paid user can PUT and GET an ordered broadcast list; free user with missing `woleh.place.broadcast` gets 403 on every broadcast endpoint.

---

### Step 2.5 — Matching service

`MatchingService` computes name intersections and hands off to the WebSocket dispatch layer (step 2.6):

- **`dispatchBroadcastMatches(broadcastUserId, normalizedBroadcastNames)`:**
  - Load all `user_place_lists` rows with `list_type = WATCH` where `normalized_names` intersects `normalizedBroadcastNames`.
  - For each matching watcher: compute `matchedNames` (the normalized intersection); call `WsSessionRegistry.sendMatchEvent(watcherUserId, matchedNames, broadcastUserId, "broadcast_to_watch")`.
  - Also notify the broadcaster (self): `WsSessionRegistry.sendMatchEvent(broadcastUserId, matchedNames, watcherUserId, "broadcast_to_watch")`.

- **`dispatchWatchMatches(watchUserId, normalizedWatchNames)`:**
  - Load all `user_place_lists` rows with `list_type = BROADCAST` where `normalized_names` intersects `normalizedWatchNames`.
  - For each matching broadcaster: compute `matchedNames`; notify the watcher: `WsSessionRegistry.sendMatchEvent(watchUserId, matchedNames, broadcastUserId, "broadcast_to_watch")`.
  - Also notify the broadcaster: `WsSessionRegistry.sendMatchEvent(broadcastUserId, matchedNames, watchUserId, "broadcast_to_watch")`.

- **Intersection query:** A simple `findAllByListType` + in-memory intersection is correct for v1. If performance becomes a concern later, an ADR may introduce a PostgreSQL `jsonb` operator query or a separate normalized-names join table. Document this in a TODO comment.

- Add `MatchingServiceTest` (unit): mock repository; verify correct counterparty lists are identified; verify empty broadcast → no events; verify disjoint lists → no events; verify intersection of two names → `matchedNames` correct.

**Implementation:** `MatchingService` (`odm.clarity.woleh.places.service.MatchingService`); `MatchEvent` record (`matchedNames`, `counterpartyUserId`, `kind`); `MatchingServiceTest`.

**Done when:** unit tests pass; `MatchingService` is called from `PlaceListService` after every successful PUT.

---

### Step 2.6 — WebSocket endpoint: `/ws/v1/transit`

Implement the authenticated WebSocket channel per [API_CONTRACT.md](./API_CONTRACT.md) §8 and [ADR 0001](./adr/0001-websocket-authentication.md):

- **Spring WebSocket configuration** (raw — not STOMP): register a `TextWebSocketHandler` at `/ws/v1/transit`; add a `HandshakeInterceptor` that reads `?access_token=<jwt>` from the query string, validates it with `JwtService`, checks the user has `woleh.place.watch` or `woleh.place.broadcast`, and stores the `userId` in the handshake attributes. Reject with HTTP 403 if validation fails (the WebSocket upgrade is a standard HTTP GET; return 403 before the upgrade completes).
- **`WsSessionRegistry`**: thread-safe `ConcurrentHashMap<String userId, WebSocketSession>`; exposed as a Spring `@Component`. Register on `afterConnectionEstablished`; deregister on `afterConnectionClosed`.
- **Message envelope**: send JSON `{ "type": "...", "data": ... }` — serialize with Jackson.
- **`WsEnvelope<T>` record**: `type` (String), `data` (T); used server-side to build outgoing messages.
- **Heartbeat**: a `@Scheduled` task (15 s interval) iterates all open sessions in `WsSessionRegistry` and sends `{ "type": "heartbeat", "data": "ping" }`. Remove dead sessions (send throws) during this loop.
- **Inbound messages**: ignore all inbound text for v1 (log at `DEBUG`; do not echo back). Forward compatibility: parse envelope `type` only; unknown types are no-ops.
- **`SecurityConfig`**: permit `/ws/v1/transit` without JWT-filter chain auth (the handshake interceptor handles auth; Spring Security's HTTP filter cannot intercept WS upgrade correctly with `?access_token`).

**Implementation:** `WsConfig` (`WebSocketConfigurer`); `TransitWebSocketHandler` (`TextWebSocketHandler`); `JwtHandshakeInterceptor`; `WsSessionRegistry`; `WsHeartbeatScheduler` (`@Scheduled`, `@EnableScheduling` on config); `WsEnvelope` record; `WsAuthIntegrationTest` (upgrade with valid token → 101; upgrade with missing/invalid token → 403; upgrade with token lacking both place permissions → 403).

**Done when:** a WebSocket client can connect with a valid JWT; heartbeats arrive at 15 s; a client without required permissions is rejected at handshake.

---

### Step 2.7 — Realtime match dispatch (connect matching to WebSocket)

Wire `MatchingService` → `WsSessionRegistry` so match events flow to connected clients:

- Update `WsSessionRegistry` to expose `sendMatchEvent(userId, matchedNames, counterpartyUserId, kind)`: if the user has an open session, serialize and send `{ "type": "match", "data": { "matchedNames": [...], "counterpartyUserId": "...", "kind": "broadcast_to_watch" } }`; if no open session, silently skip (the user will see their current matches when they open the app and connect via WS).
- `MatchingService` (step 2.5) already calls `WsSessionRegistry.sendMatchEvent` — this step ensures the wire-up is live-tested end-to-end.
- Add an integration test **`MatchDispatchIntegrationTest`**: spin up the server with `@SpringBootTest`; use a test WS client (e.g. `StandardWebSocketClient`) to connect as user A (watcher); have user B PUT a broadcast list that overlaps A's watch list; assert A's WS client receives a `match` message with the correct `matchedNames`.

**Implementation:** `WsSessionRegistry.sendMatchEvent(...)` implementation; `MatchDispatchIntegrationTest` (end-to-end test via embedded server, two test users, two WS sessions, overlapping place lists).

**Done when:** end-to-end integration test passes: broadcast PUT → watcher receives WS `match` event.

---

### Step 2.8 — Tests and API artifacts

- **Unit tests** (if not already in earlier steps): `PlaceNameNormalizerTest`, `MatchingServiceTest`, `WsAuthIntegrationTest`, `MatchDispatchIntegrationTest`.
- **Integration tests**: `WatchListIntegrationTest`, `BroadcastListIntegrationTest`, `SubscriptionStatusIntegrationTest` extended if place limits changed.
- **`server/api-tests/phase2.http`**: connect WS → PUT watch list → PUT broadcast list (from another user) → observe match (manual flow using IntelliJ HTTP Client + WS support or note WS step manually). Include `@watchToken` and `@broadcastToken` variables; chain place list reads after PUTs.
- Update **`http-client.env.json`** with any new Phase 2 env variables.

**Done when:** CI is green; `.http` file documents the watch → broadcast → match happy path for manual QA.

---

## 3. Mobile (Flutter)

### Step 3.1 — `normalizePlaceName` Dart utility + shared test vectors

Implement the same four-step pipeline ([PLACE_NAMES.md](./PLACE_NAMES.md) §1) in Dart:

1. **Trim** — `input.trim()`.
2. **NFC** — use the [`characters`](https://pub.dev/packages/characters) package or [`unorm_dart`](https://pub.dev/packages/unorm) / [`diacritic`](https://pub.dev/packages/diacritic) for NFC if the Dart runtime does not expose it directly. Document the chosen package in `pubspec.yaml` comments.
3. **Case fold** — `result.toLowerCase()` (sufficient for Latin-script Ghana-English place names in v1; document the limitation).
4. **Collapse internal whitespace** — `result.replaceAll(RegExp(r'\s+'), ' ').trim()`.

- Expose in `mobile/lib/core/place_name_normalizer.dart` as a top-level function `normalizePlaceName(String input): String`.
- Add `validatePlaceName(String raw): String?` returning an error string (or null if valid); used by form fields.
- Add `test/core/place_name_normalizer_test.dart` with the three canonical test vectors from [PLACE_NAMES.md](./PLACE_NAMES.md) §5 plus the same edge cases as the server unit test — ensures client and server produce identical normalized forms.

**Implementation:** `mobile/lib/core/place_name_normalizer.dart`; `test/core/place_name_normalizer_test.dart`.

**Done when:** all test vectors pass; `normalizePlaceName` is idempotent.

---

### Step 3.2 — Place-list DTOs and repository

Wire the REST place-list endpoints into the mobile data layer:

- **`PlaceNamesDto`** (`mobile/lib/features/places/data/place_names_dto.dart`): `{ List<String> names }` — both watch and broadcast use the same shape.
- **`PlaceListRepository`** (`mobile/lib/features/places/data/place_list_repository.dart`): `keepAlive` provider; methods:
  - `getWatchList(): Future<List<String>>`
  - `putWatchList(List<String> names): Future<List<String>>`
  - `getBroadcastList(): Future<List<String>>`
  - `putBroadcastList(List<String> names): Future<List<String>>`
- Map `AppError` types from HTTP 400 / 403 responses (`PlaceLimitError`, `PlaceValidationError` extending the sealed failure hierarchy in `app_error.dart`).

**Implementation:** `place_names_dto.dart`; `place_list_repository.dart`; `app_error.dart` extended with `PlaceLimitError` and `PlaceValidationError`.

**Done when:** `PlaceListRepository` methods compile and map errors correctly; unit-testable with stub HTTP responses.

---

### Step 3.3 — Watch screen

Build the watch-list editor for users with `woleh.place.watch`:

- **`WatchNotifier`** (`mobile/lib/features/places/presentation/watch_notifier.dart`): `@riverpod` async notifier; loads list on init (`PlaceListRepository.getWatchList`); exposes `add(String name)`, `remove(String name)`, `save()` methods; `save()` calls `putWatchList` with current list and refreshes on success.
- **`WatchScreen`** (`mobile/lib/features/places/presentation/watch_screen.dart`):
  - Text field for adding a name; client-side preview: show `normalizePlaceName(input)` under the field so the user sees what the server will match on.
  - List of added names with dismiss-to-remove (`Dismissible`); display user-entered form; show normalized preview in a subtitle.
  - "Save" button (calls `notifier.save()`); loading and error states (surface `PlaceLimitError` as "You've reached your watch limit — upgrade to add more").
  - Pull-to-refresh reloads from server.
- Route: `/watch` — accessible only to users with `woleh.place.watch`; redirect to Plans if missing (reuse `PermissionGuard` from Phase 1).
- Entry point: add a **"My Watch List"** entry to the home screen's "Actions" section alongside the existing "Broadcast" entry (using `PermissionGatedButton`).

**Implementation:** `watch_notifier.dart`; `watch_screen.dart`; router `/watch` route; home screen entry updated; `watch_screen_test.dart` (stub notifier: idle layout, add name, remove name, save loading state, over-limit error, empty-list state).

**Done when:** a user with `woleh.place.watch` can add/remove names, save to server, and re-open the screen to see saved names.

---

### Step 3.4 — Broadcast screen

Build the broadcast-list editor for users with `woleh.place.broadcast`:

- **`BroadcastNotifier`** (`mobile/lib/features/places/presentation/broadcast_notifier.dart`): analogous to `WatchNotifier` but list is **ordered** (sequence matters); expose `reorder(int oldIndex, int newIndex)` for drag-to-reorder UX.
- **`BroadcastScreen`** (`mobile/lib/features/places/presentation/broadcast_screen.dart`):
  - Text field to append a new stop; normalized preview as in the watch screen.
  - `ReorderableListView` so the operator can drag stops into drive-through order; dismiss-to-remove.
  - "Save" button; loading/error states (surface `PlaceLimitError`).
  - Pull-to-refresh.
- Route: `/broadcast` — already gated behind `woleh.place.broadcast` from Phase 1 (was a placeholder); replace the placeholder with the real `BroadcastScreen`.

**Implementation:** `broadcast_notifier.dart`; `broadcast_screen.dart` replacing the Phase 1 placeholder; `broadcast_screen_test.dart` (idle layout, add, reorder, save loading, over-limit error).

**Done when:** the `/broadcast` route now loads and saves a real broadcast list; Phase 1 placeholder is replaced.

---

### Step 3.5 — WebSocket client

Connect to `/ws/v1/transit` and handle the message envelope:

- **`WsClient`** (`mobile/lib/core/ws_client.dart`): `keepAlive` `@Riverpod` notifier; lifecycle:
  - `connect()`: open `WebSocketChannel` to `wss://<host>/ws/v1/transit?access_token=<jwt>`; start listening to the stream.
  - `disconnect()`: close channel; clear reconnect timer.
  - **Reconnect with backoff:** on `onDone` / `onError`, schedule reconnect after `min(baseDelay * 2^attempt, maxDelay)` (e.g. base 2 s, max 60 s). Reset attempt counter on successful message receipt.
  - **Heartbeat handling:** `{ "type": "heartbeat" }` messages are silently discarded (no reply needed for server-push heartbeat model).
  - **Unknown type:** parse `type` field; if unknown, log at `DEBUG` and ignore — forward compatibility.
  - Expose a `Stream<WsMessage>` of decoded messages (excluding heartbeats) to interested widgets.
- **`WsMessage`** sealed class: `MatchMessage({ List<String> matchedNames, String counterpartyUserId, String kind })` plus `UnknownMessage(String type)` for forward-compat.
- **Auth integration:** `WsClient` reads `accessToken` from `authStateProvider`; re-connects automatically when the token changes (e.g. after new login).
- **`WsClientProvider`**: starts connection when the user is authenticated (watch `authStateProvider`; connect when token is non-null; disconnect on sign-out).

**Implementation:** `ws_client.dart`; `ws_message.dart` (sealed); `main.dart` / `ProviderScope` ensures `WsClientProvider` is eagerly initialized after auth; `ws_client_test.dart` (unit: mock channel; verify backoff schedule; verify heartbeat filtered; verify unknown type ignored; verify `MatchMessage` parsed correctly).

**Done when:** the WS client connects on login, receives heartbeats without surfacing them to UI, and reconnects after a simulated disconnect.

---

### Step 3.6 — Match event UX

Surface incoming `match` events to the user:

- **`MatchNotifier`** (`mobile/lib/features/places/presentation/match_notifier.dart`): `keepAlive` `@riverpod` notifier that listens to `WsClient`'s message stream; accumulates a `List<MatchMessage>` (capped at last 20 for UI); clears on sign-out.
- **Match banner on `HomeScreen`**: show a "New match" card when `matchNotifierProvider` has entries; each card displays:
  - "A bus is heading through: [matched names]" (for a watcher receiving `broadcast_to_watch`).
  - Tap to dismiss or navigate to the watch screen.
- **Watch screen integration**: if the user is on the watch screen when a match arrives, show a `SnackBar` ("Match found — a vehicle covers [name]") via the `WsClient` stream directly inside `WatchScreen`.
- **Broadcast screen integration**: similarly, notify the broadcaster via `SnackBar` when a watcher's list intersects their broadcast list.

**Implementation:** `match_notifier.dart`; update `home_screen.dart` with match card section; update `watch_screen.dart` and `broadcast_screen.dart` with `SnackBar` on match; `match_notifier_test.dart` (stub `WsClient`; verify match list accumulates; verify cap at 20; verify clear on sign-out).

**Done when:** a watcher connected via WS sees a home-screen match card when a broadcaster PUTs a list that overlaps their watch names.

---

### Step 3.7 — Tests

- `test/core/place_name_normalizer_test.dart` — normalization test vectors (step 3.1).
- `test/features/places/watch_screen_test.dart` — watch screen widget tests (step 3.3).
- `test/features/places/broadcast_screen_test.dart` — broadcast screen widget tests (step 3.4).
- `test/core/ws_client_test.dart` — WS client unit tests: backoff, heartbeat filter, unknown type, match parse (step 3.5).
- `test/features/places/match_notifier_test.dart` — match accumulation and clear-on-signout (step 3.6).
- Router tests extended: `/watch` inaccessible to user without `woleh.place.watch`; `/broadcast` now routes to real screen not placeholder.

**Done when:** CI is green; all new screens and the WS client have test coverage.

---

## 4. Definition of done (Phase 2)

- [ ] `PlaceNameNormalizer` (server) and `normalizePlaceName` (Dart) produce identical output for all [PLACE_NAMES.md](./PLACE_NAMES.md) §5 test vectors.
- [ ] `GET` + `PUT /api/v1/me/places/watch` enforces permission, limit, dedupe; returns saved list.
- [ ] `GET` + `PUT /api/v1/me/places/broadcast` enforces permission, limit, ordered dedupe; returns saved list.
- [ ] Free user: capped at 5 watch names; 403 on attempt to exceed; no broadcast access.
- [ ] Paid user: up to 50 watch names; up to 50 ordered broadcast names.
- [ ] `MatchingService` correctly computes non-empty name intersection and dispatches match events.
- [ ] `/ws/v1/transit` rejects upgrade without valid JWT or without place permissions; accepts valid JWT with either place permission.
- [ ] Heartbeat sent to all open WS sessions every 15 s.
- [ ] End-to-end: watcher connected via WS receives `match` event when broadcaster PUTs an overlapping list.
- [ ] Mobile Watch screen: add/remove names, save, reload; preview shows normalized form; over-limit error shown.
- [ ] Mobile Broadcast screen: ordered add/reorder/remove, save, reload; replaces Phase 1 placeholder.
- [ ] Mobile WS client: connects on login; reconnects with backoff on drop; heartbeats discarded; unknown types ignored.
- [ ] Mobile home screen displays match card when a `match` event arrives via WS.
- [ ] CI passes: server + mobile tests green.
- [ ] `server/api-tests/phase2.http` documents the watch → broadcast → match flow for manual QA.

---

## 5. Document history

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2026-04-09 | Initial Phase 2 codable breakdown |
| 0.2 | 2026-04-09 | Step 2.1 implemented: `PlaceNameNormalizer` (trim → NFC → case fold → collapse whitespace), `PlaceNameValidationException` → 400 in `GlobalExceptionHandler`, `PlaceNameNormalizerTest` (17 tests — 3 spec vectors + 14 edge cases) |

When Phase 2 is complete, update [PRD.md](./PRD.md) phase table to "✅ Complete" and note any deviations (e.g. normalization library chosen for Dart NFC, in-memory vs DB intersection query, final `match` event field names).
