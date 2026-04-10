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

### Step 2.2 — Place-list DB schema ✅

Add one table via Flyway migration:

- **`user_place_lists`**: `id` (PK), `user_id` (FK → `users`, non-null), `list_type` (varchar: `watch` | `broadcast`), `display_names` (JSON array of strings — user-entered display form), `normalized_names` (JSON array of strings — normalized form, stored for efficient matching queries), `updated_at`.
- Unique constraint on `(user_id, list_type)` — at most one watch row and one broadcast row per user.

Store both display and normalized forms: display form is returned to the client; normalized form is used for matching queries without re-normalizing at read time. If the normalization algorithm changes, a migration must re-normalize stored values (document this risk in the migration comment).

**Implementation:** Flyway [`V5__user_place_lists.sql`](../server/src/main/resources/db/migration/V5__user_place_lists.sql); JPA entity [`UserPlaceList`](../server/src/main/java/odm/clarity/woleh/model/UserPlaceList.java); Spring Data repository [`UserPlaceListRepository`](../server/src/main/java/odm/clarity/woleh/repository/UserPlaceListRepository.java) (`findByUser_IdAndListType`, `findAllByListType`); enum [`PlaceListType`](../server/src/main/java/odm/clarity/woleh/model/PlaceListType.java) (`WATCH`, `BROADCAST`); reuses existing `StringListConverter` for JSON ↔ `List<String>`; [`UserPlaceListRepositoryTest`](../server/src/test/java/odm/clarity/woleh/places/UserPlaceListRepositoryTest.java) — 9 tests.

**Done when:** migrations apply cleanly; a `UserPlaceListRepository` round-trip test verifies both list types save and reload correctly. ✅

---

### Step 2.3 — `GET` + `PUT /api/v1/me/places/watch` ✅

Implement per [API_CONTRACT.md](./API_CONTRACT.md) §6.7–§6.8:

- **`GET /api/v1/me/places/watch`**: requires `woleh.place.watch`; return `{ "names": [...] }` from `display_names` (insertion order preserved); return empty list if no row exists.
- **`PUT /api/v1/me/places/watch`**: requires `woleh.place.watch`; body `{ "names": [...] }`.
  - Validate each name with `PlaceNameNormalizer.validatePlaceName`.
  - Compute normalized forms; dedupe by normalized equality (keep first occurrence of each normalized form, preserving display name of the first occurrence).
  - Enforce `limits.placeWatchMax` after dedupe → **403** with `code: "OVER_LIMIT"` if exceeded.
  - Upsert the `user_place_lists` row (create if absent, replace lists if present).
  - After a successful save, call `MatchingService.dispatchWatchMatches(userId, normalizedNames)` (step 2.5) to push real-time events.
  - Return the saved list: `{ "names": [...] }` (display form, deduped).

**Implementation:** [`PlaceListController`](../server/src/main/java/odm/clarity/woleh/places/PlaceListController.java) at `/api/v1/me/places`; [`PlaceNamesRequest`](../server/src/main/java/odm/clarity/woleh/places/dto/PlaceNamesRequest.java) / [`PlaceNamesResponse`](../server/src/main/java/odm/clarity/woleh/places/dto/PlaceNamesResponse.java) DTOs; [`PlaceListService`](../server/src/main/java/odm/clarity/woleh/places/PlaceListService.java) (`getWatchList` / `putWatchList`); [`PermissionDeniedException`](../server/src/main/java/odm/clarity/woleh/common/error/PermissionDeniedException.java) → 403 `PERMISSION_DENIED`; [`PlaceLimitExceededException`](../server/src/main/java/odm/clarity/woleh/common/error/PlaceLimitExceededException.java) → 403 `OVER_LIMIT`; [`MatchingService`](../server/src/main/java/odm/clarity/woleh/places/MatchingService.java) stub (no-op `dispatchWatchMatches` / `dispatchBroadcastMatches`); [`WatchListIntegrationTest`](../server/src/test/java/odm/clarity/woleh/places/WatchListIntegrationTest.java) — 16 tests.

**Done when:** a paid user can PUT and GET a watch list; free user with capped list gets 403 on exceeding 5 names; empty list PUT clears it. ✅

---

### Step 2.4 — `GET` + `PUT /api/v1/me/places/broadcast` ✅

Implement per [API_CONTRACT.md](./API_CONTRACT.md) §6.9–§6.10 — mirrors step 2.3 but for broadcast:

- **`GET /api/v1/me/places/broadcast`**: requires `woleh.place.broadcast`; return `{ "names": [...] }` in stored order (sequence is significant); **403** for users missing the permission.
- **`PUT /api/v1/me/places/broadcast`**: requires `woleh.place.broadcast`.
  - Same validation as watch: per-name length, non-empty after trim.
  - Dedupe by normalized equality (PRD §13.2: "dedupe on save recommended"); for broadcast, if duplicate normalized names appear and product policy is **400**, return `400` with a clear message. Default: reject with 400 per API contract §6.10 note.
  - Enforce `limits.placeBroadcastMax` after dedupe.
  - Upsert the broadcast row; order is preserved (stored as JSON array).
  - After save, call `MatchingService.dispatchBroadcastMatches(userId, normalizedNames)` (step 2.5).
  - Return `{ "names": [...] }` (display form, stored order).

**Implementation:** [`PlaceListService`](../server/src/main/java/odm/clarity/woleh/places/PlaceListService.java) updated with `getBroadcastList` / `putBroadcastList` (validate → reject duplicate normalized names with 400 → limit check → upsert → `dispatchBroadcastMatches` stub); [`PlaceListController`](../server/src/main/java/odm/clarity/woleh/places/PlaceListController.java) updated with `GET`+`PUT /broadcast`; [`BroadcastListIntegrationTest`](../server/src/test/java/odm/clarity/woleh/places/BroadcastListIntegrationTest.java) — 17 tests.

**Done when:** a paid user can PUT and GET an ordered broadcast list; free user with missing `woleh.place.broadcast` gets 403 on every broadcast endpoint. ✅

---

### Step 2.5 — Matching service ✅

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

**Implementation:** [`MatchEvent`](../server/src/main/java/odm/clarity/woleh/places/MatchEvent.java) record; [`WsSessionRegistry`](../server/src/main/java/odm/clarity/woleh/ws/WsSessionRegistry.java) stub in `ws/` (no-op `sendMatchEvent`; completed in steps 2.6–2.7); `userId` read-only FK column added to [`UserPlaceList`](../server/src/main/java/odm/clarity/woleh/model/UserPlaceList.java) to avoid LAZY load in service; [`MatchingService`](../server/src/main/java/odm/clarity/woleh/places/MatchingService.java) (`@Transactional(readOnly=true)`, in-memory intersection, notifies both parties per match); [`MatchingServiceTest`](../server/src/test/java/odm/clarity/woleh/places/MatchingServiceTest.java) — 11 unit tests.

**Done when:** unit tests pass; `MatchingService` is called from `PlaceListService` after every successful PUT. ✅

---

### Step 2.6 — WebSocket endpoint: `/ws/v1/transit` ✅

Implement the authenticated WebSocket channel per [API_CONTRACT.md](./API_CONTRACT.md) §8 and [ADR 0001](./adr/0001-websocket-authentication.md):

- **Spring WebSocket configuration** (raw — not STOMP): register a `TextWebSocketHandler` at `/ws/v1/transit`; add a `HandshakeInterceptor` that reads `?access_token=<jwt>` from the query string, validates it with `JwtService`, checks the user has `woleh.place.watch` or `woleh.place.broadcast`, and stores the `userId` in the handshake attributes. Reject with HTTP 403 if validation fails (the WebSocket upgrade is a standard HTTP GET; return 403 before the upgrade completes).
- **`WsSessionRegistry`**: thread-safe `ConcurrentHashMap<Long userId, WebSocketSession>`; exposed as a Spring `@Component`. Register on `afterConnectionEstablished`; deregister on `afterConnectionClosed`.
- **Message envelope**: send JSON `{ "type": "...", "data": ... }` — serialize with Jackson.
- **`WsEnvelope<T>` record**: `type` (String), `data` (T); used server-side to build outgoing messages.
- **Heartbeat**: a `@Scheduled` task (15 s interval) iterates all open sessions in `WsSessionRegistry` and sends `{ "type": "heartbeat", "data": "ping" }`. Remove dead sessions (send throws) during this loop.
- **Inbound messages**: ignore all inbound text for v1 (log at `DEBUG`; do not echo back). Forward compatibility: parse envelope `type` only; unknown types are no-ops.
- **`SecurityConfig`**: permit `/ws/**` without JWT-filter chain auth (the handshake interceptor handles auth; Spring Security's HTTP filter cannot intercept WS upgrade correctly with `?access_token`).

**Implementation:** [`WsConfig`](../server/src/main/java/odm/clarity/woleh/ws/WsConfig.java) (`@Configuration @EnableWebSocket @EnableScheduling`); [`TransitWebSocketHandler`](../server/src/main/java/odm/clarity/woleh/ws/TransitWebSocketHandler.java) (`TextWebSocketHandler` — register/deregister in `WsSessionRegistry`, ignore inbound); [`JwtHandshakeInterceptor`](../server/src/main/java/odm/clarity/woleh/ws/JwtHandshakeInterceptor.java) (query-param token → `JwtService` → `EntitlementService` → 403 on reject, stores `userId` in attributes); [`WsSessionRegistry`](../server/src/main/java/odm/clarity/woleh/ws/WsSessionRegistry.java) updated with `ConcurrentHashMap`, `register`/`deregister`, `sendToAllOpen` for heartbeat; [`WsHeartbeatScheduler`](../server/src/main/java/odm/clarity/woleh/ws/WsHeartbeatScheduler.java) (`@Scheduled(fixedDelay=15_000)`, evicts dead sessions on send error); [`WsEnvelope<T>`](../server/src/main/java/odm/clarity/woleh/ws/WsEnvelope.java) record; `SecurityConfig` updated with `.requestMatchers("/ws/**").permitAll()`; [`WsAuthIntegrationTest`](../server/src/test/java/odm/clarity/woleh/ws/WsAuthIntegrationTest.java) — 5 tests using Java 11 `HttpClient` WS API (`RANDOM_PORT`, `@MockBean EntitlementService`).

**Done when:** a WebSocket client can connect with a valid JWT; heartbeats arrive at 15 s; a client without required permissions is rejected at handshake. ✅

---

### Step 2.7 — Realtime match dispatch (connect matching to WebSocket) ✅

Wire `MatchingService` → `WsSessionRegistry` so match events flow to connected clients:

- Update `WsSessionRegistry` to expose `sendMatchEvent(userId, matchedNames, counterpartyUserId, kind)`: if the user has an open session, serialize and send `{ "type": "match", "data": { "matchedNames": [...], "counterpartyUserId": "...", "kind": "broadcast_to_watch" } }`; if no open session, silently skip (the user will see their current matches when they open the app and connect via WS).
- `MatchingService` (step 2.5) already calls `WsSessionRegistry.sendMatchEvent` — this step ensures the wire-up is live-tested end-to-end.
- Add an integration test **`MatchDispatchIntegrationTest`**: spin up the server with `@SpringBootTest`; use a test WS client (e.g. `StandardWebSocketClient`) to connect as user A (watcher); have user B PUT a broadcast list that overlaps A's watch list; assert A's WS client receives a `match` message with the correct `matchedNames`.

**Implementation:** [`WsSessionRegistry.sendMatchEvent`](../server/src/main/java/odm/clarity/woleh/ws/WsSessionRegistry.java) implemented (`ObjectMapper` injected; serialize `MatchEvent` into `WsEnvelope<MatchEvent>`; send to session if open; deregister on `IOException`; skip silently if no session); [`MatchEvent`](../server/src/main/java/odm/clarity/woleh/ws/MatchEvent.java) moved from `places/` to `ws/` to avoid circular package dependency; [`MatchDispatchIntegrationTest`](../server/src/test/java/odm/clarity/woleh/ws/MatchDispatchIntegrationTest.java) — 2 end-to-end tests (`RANDOM_PORT`, `TestRestTemplate`, Java 11 `HttpClient` WS API).

**Done when:** end-to-end integration test passes: broadcast PUT → watcher receives WS `match` event. ✅

---

### Step 2.8 — Tests and API artifacts ✅

- **Unit tests** (if not already in earlier steps): `PlaceNameNormalizerTest`, `MatchingServiceTest`, `WsAuthIntegrationTest`, `MatchDispatchIntegrationTest`.
- **Integration tests**: `WatchListIntegrationTest`, `BroadcastListIntegrationTest`, `SubscriptionStatusIntegrationTest` extended if place limits changed.
- **`server/api-tests/phase2.http`**: connect WS → PUT watch list → PUT broadcast list (from another user) → observe match (manual flow using IntelliJ HTTP Client + WS support or note WS step manually). Include `@watchToken` and `@broadcastToken` variables; chain place list reads after PUTs.
- Update **`http-client.env.json`** with any new Phase 2 env variables.

**Done when:** CI is green; `.http` file documents the watch → broadcast → match happy path for manual QA.

---

## 3. Mobile (Flutter)

### Step 3.1 — `normalizePlaceName` Dart utility + shared test vectors ✅

Implement the same four-step pipeline ([PLACE_NAMES.md](./PLACE_NAMES.md) §1) in Dart:

1. **Trim** — `input.trim()`.
2. **NFC** — use the [`characters`](https://pub.dev/packages/characters) package or [`unorm_dart`](https://pub.dev/packages/unorm) / [`diacritic`](https://pub.dev/packages/diacritic) for NFC if the Dart runtime does not expose it directly. Document the chosen package in `pubspec.yaml` comments.
3. **Case fold** — `result.toLowerCase()` (sufficient for Latin-script Ghana-English place names in v1; document the limitation).
4. **Collapse internal whitespace** — `result.replaceAll(RegExp(r'\s+'), ' ').trim()`.

- Expose in `mobile/lib/core/place_name_normalizer.dart` as a top-level function `normalizePlaceName(String input): String`.
- Add `validatePlaceName(String raw): String?` returning an error string (or null if valid); used by form fields.
- Add `test/core/place_name_normalizer_test.dart` with the three canonical test vectors from [PLACE_NAMES.md](./PLACE_NAMES.md) §5 plus the same edge cases as the server unit test — ensures client and server produce identical normalized forms.

**Implementation:** `unorm_dart 0.3.2` added to `pubspec.yaml` (pure-Dart NFC via Unicode 17.0 data); [`mobile/lib/core/place_name_normalizer.dart`](../mobile/lib/core/place_name_normalizer.dart) — `normalizePlaceName(String) → String` (4-step pipeline: trim → `unorm.nfc` → `toLowerCase` → collapse whitespace), `validatePlaceName(String?) → String?` (empty/null check, 200-code-point cap; mirrors server constants); [`test/core/place_name_normalizer_test.dart`](../mobile/test/core/place_name_normalizer_test.dart) — 17 tests (3 spec vectors + 14 edge cases: empty, blank, tab, case, exact output, mixed whitespace, idempotency, Ghana-English names, validate null/empty/blank/over-limit/valid/max).

**Done when:** all test vectors pass; `normalizePlaceName` is idempotent. ✅

---

### Step 3.2 — Place-list DTOs and repository ✅

Wire the REST place-list endpoints into the mobile data layer:

- **`PlaceNamesDto`** (`mobile/lib/features/places/data/place_names_dto.dart`): `{ List<String> names }` — both watch and broadcast use the same shape.
- **`PlaceListRepository`** (`mobile/lib/features/places/data/place_list_repository.dart`): `keepAlive` provider; methods:
  - `getWatchList(): Future<List<String>>`
  - `putWatchList(List<String> names): Future<List<String>>`
  - `getBroadcastList(): Future<List<String>>`
  - `putBroadcastList(List<String> names): Future<List<String>>`
- Map `AppError` types from HTTP 400 / 403 responses (`PlaceLimitError`, `PlaceValidationError` extending the sealed failure hierarchy in `app_error.dart`).

**Implementation:** [`app_error.dart`](../mobile/lib/core/app_error.dart) extended with `PlaceValidationError` (400 `VALIDATION_ERROR`) and `PlaceLimitError` (403 `OVER_LIMIT`); [`api_client.dart`](../mobile/lib/core/api_client.dart) — `_ErrorInterceptor` renamed to `AppErrorInterceptor` (public) and updated to map 400/403 with server `code` field; [`place_names_dto.dart`](../mobile/lib/features/places/data/place_names_dto.dart) — simple `PlaceNamesDto` with `fromJson`/`toJson`; [`place_list_repository.dart`](../mobile/lib/features/places/data/place_list_repository.dart) — `@Riverpod(keepAlive: true)` with `getWatchList`, `putWatchList`, `getBroadcastList`, `putBroadcastList`; [`place_list_repository_test.dart`](../mobile/test/features/places/place_list_repository_test.dart) — 11 tests (`_MockAdapter` + `AppErrorInterceptor`: happy-path parsing for all 4 methods, 401 → `UnauthorizedError`, 403 `PERMISSION_DENIED` → `ForbiddenError`, 400 `VALIDATION_ERROR` → `PlaceValidationError`, 403 `OVER_LIMIT` → `PlaceLimitError`, broadcast duplicate 400).

**Done when:** `PlaceListRepository` methods compile and map errors correctly; unit-testable with stub HTTP responses. ✅

---

### Step 3.3 — Watch screen ✅

Build the watch-list editor for users with `woleh.place.watch`:

- **`WatchNotifier`** (`mobile/lib/features/places/presentation/watch_notifier.dart`): `@riverpod` async notifier; loads list on init (`PlaceListRepository.getWatchList`); exposes `add(String name)`, `remove(String name)`, `save()` methods; `save()` calls `putWatchList` with current list and refreshes on success.
- **`WatchScreen`** (`mobile/lib/features/places/presentation/watch_screen.dart`):
  - Text field for adding a name; client-side preview: show `normalizePlaceName(input)` under the field so the user sees what the server will match on.
  - List of added names with dismiss-to-remove (`Dismissible`); display user-entered form; show normalized preview in a subtitle.
  - "Save" button (calls `notifier.save()`); loading and error states (surface `PlaceLimitError` as "You've reached your watch limit — upgrade to add more").
  - Pull-to-refresh reloads from server.
- Route: `/watch` — accessible only to users with `woleh.place.watch`; redirect to Plans if missing (reuse `PermissionGuard` from Phase 1).
- Entry point: add a **"My Watch List"** entry to the home screen's "Actions" section alongside the existing "Broadcast" entry (using `PermissionGatedButton`).

**Implementation:** [`watch_notifier.dart`](../mobile/lib/features/places/presentation/watch_notifier.dart) — sealed `WatchState` (`WatchLoading` / `WatchReady` / `WatchLoadError`); `@riverpod` notifier with `add`, `remove`, `save`, `refresh`; sentinel `copyWith` for nullable `saveError`; [`watch_screen.dart`](../mobile/lib/features/places/presentation/watch_screen.dart) — `ConsumerStatefulWidget`; state-driven body; `_AddNameField` with `ValueListenableBuilder` normalized preview; `Dismissible` name tiles; `_SaveErrorBanner` surfaces `PlaceLimitError` with upgrade message; `_SaveBar` with in-button loading indicator; pull-to-refresh; [`router.dart`](../mobile/lib/app/router.dart) — `/watch` added to `_permissionGuards` and routes list; [`home_screen.dart`](../mobile/lib/features/home/presentation/home_screen.dart) — "My Watch List" `PermissionGatedButton` added above Broadcast entry; [`watch_screen_test.dart`](../mobile/test/features/places/watch_screen_test.dart) — 7 widget tests (idle layout, add-field present, normalized preview, remove buttons, save loading, over-limit error, empty state).

**Done when:** a user with `woleh.place.watch` can add/remove names, save to server, and re-open the screen to see saved names. ✅

---

### Step 3.4 — Broadcast screen ✅

Build the broadcast-list editor for users with `woleh.place.broadcast`:

- **`BroadcastNotifier`** (`mobile/lib/features/places/presentation/broadcast_notifier.dart`): analogous to `WatchNotifier` but list is **ordered** (sequence matters); expose `reorder(int oldIndex, int newIndex)` for drag-to-reorder UX.
- **`BroadcastScreen`** (`mobile/lib/features/places/presentation/broadcast_screen.dart`):
  - Text field to append a new stop; normalized preview as in the watch screen.
  - `ReorderableListView` so the operator can drag stops into drive-through order; dismiss-to-remove.
  - "Save" button; loading/error states (surface `PlaceLimitError`).
  - Pull-to-refresh.
- Route: `/broadcast` — already gated behind `woleh.place.broadcast` from Phase 1 (was a placeholder); replace the placeholder with the real `BroadcastScreen`.

**Implementation:** [`broadcast_notifier.dart`](../mobile/lib/features/places/presentation/broadcast_notifier.dart) — sealed `BroadcastState` (`BroadcastLoading` / `BroadcastReady` / `BroadcastLoadError`); `@riverpod` notifier with `add`, `remove`, `reorder` (adjusts index for `ReorderableListView`'s convention), `save`, `refresh`; [`broadcast_screen.dart`](../mobile/lib/features/places/presentation/broadcast_screen.dart) — `ConsumerStatefulWidget`; `ReorderableListView` with explicit `ReorderableDragStartListener` drag-handle icons; `Dismissible` swipe-to-remove per stop; normalized preview field; save-error banner; `_SaveBar`; pull-to-refresh; [`router.dart`](../mobile/lib/app/router.dart) — `/broadcast` now points to `BroadcastScreen` (placeholder removed); [`broadcast_screen_test.dart`](../mobile/test/features/places/broadcast_screen_test.dart) — 5 widget tests (idle layout, add field, drag handle per stop, save loading, over-limit error); [`router_redirect_test.dart`](../mobile/test/app/router_redirect_test.dart) — updated to use `_EmptyPlaceListRepository` stub so broadcast/watch screens settle in `pumpAndSettle`.

**Done when:** the `/broadcast` route now loads and saves a real broadcast list; Phase 1 placeholder is replaced. ✅

---

### Step 3.5 — WebSocket client ✅

Connect to `/ws/v1/transit` and handle the message envelope:

- **`WsClient`** (`mobile/lib/core/ws_client.dart`): `keepAlive` `@Riverpod` notifier; lifecycle:
  - `connect()`: open `WebSocketChannel` to `wss://<host>/ws/v1/transit?access_token=<jwt>`; start listening to the stream.
  - `disconnect()`: close channel; clear reconnect timer.
  - **Reconnect with backoff:** on `onDone` / `onError`, schedule reconnect after `min(baseDelay * 2^attempt, maxDelay)` (e.g. base 2 s, max 60 s). Reset attempt counter on successful message receipt.
  - **Heartbeat handling:** `{ "type": "heartbeat" }` messages are silently discarded (no reply needed for server-push heartbeat model).
  - **Unknown type:** parse `type` field; emit `UnknownMessage` for forward-compat, log at `DEBUG`.
  - Expose a `Stream<WsMessage>` of decoded messages (excluding heartbeats) to interested widgets.
  - `createChannel(Uri)` is `@visibleForTesting` overridable so tests can inject a `_FakeChannel`.
  - `onDispose` nulls `_currentToken` before closing the channel so `_scheduleReconnect` short-circuits in teardown (prevents stray timer creation inside `fakeAsync`).
- **`WsMessage`** (`mobile/lib/core/ws_message.dart`): sealed class `MatchMessage({ List<String> matchedNames, String counterpartyUserId, String kind })` plus `UnknownMessage(String type)` for forward-compat.
- **Auth integration:** `WsClient` uses `ref.listen(authStateProvider, fireImmediately: true)` — auto-connects when token is non-null, auto-disconnects on sign-out.
- **Eager init:** `WolehApp.build()` watches `wsClientProvider` (state is `void`, no rebuilds triggered) to ensure the provider is created as soon as the app renders.
- **`ws_client.dart`** also exposes `static Duration reconnectDelay(int attempt)` for white-box backoff testing.

**Implementation:**
- `mobile/lib/core/ws_message.dart` — sealed `WsMessage` hierarchy.
- `mobile/lib/core/ws_client.dart` — `@Riverpod(keepAlive: true)` notifier with connect/disconnect, backoff, heartbeat filter, message dispatch.
- `mobile/lib/core/ws_client.g.dart` — generated.
- `mobile/lib/main.dart` — `ref.watch(wsClientProvider)` added to `WolehApp.build()`.
- `mobile/pubspec.yaml` — added `web_socket_channel`.
- `mobile/test/core/ws_client_test.dart` — 6 unit tests (backoff delay table; reconnect timing via `fakeAsync`; heartbeat filtered; `UnknownMessage` emitted; `MatchMessage` fields; backoff reset on receipt).

**Done when:** the WS client connects on login, receives heartbeats without surfacing them to UI, and reconnects after a simulated disconnect. ✓ (144 mobile tests green)

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
| 0.3 | 2026-04-09 | Step 2.2 implemented: `V5__user_place_lists.sql` (unique constraint on user+type, indexes on user_id and list_type), `PlaceListType` enum (`WATCH`/`BROADCAST`), `UserPlaceList` entity (display + normalized names via `StringListConverter`), `UserPlaceListRepository` (`findByUser_IdAndListType`, `findAllByListType`), `UserPlaceListRepositoryTest` (9 tests — round-trips, isolation, empty-list JSON) |
| 0.4 | 2026-04-09 | Step 2.3 implemented: `PermissionDeniedException` → 403 `PERMISSION_DENIED`, `PlaceLimitExceededException` → 403 `OVER_LIMIT`, `PlaceNamesRequest`/`PlaceNamesResponse` DTOs, `MatchingService` no-op stub, `PlaceListService` (`getWatchList`/`putWatchList` — validate, dedupe, limit, upsert, dispatch stub), `PlaceListController` (`GET`+`PUT /watch`), `WatchListIntegrationTest` (16 tests — auth, permission guard via `@MockBean`, validation, limit, dedupe, round-trip, clear) |
| 0.5 | 2026-04-09 | Step 2.4 implemented: `getBroadcastList`/`putBroadcastList` added to `PlaceListService` (validate → reject duplicate normalized names with 400 → limit → upsert → dispatch stub); `GET`+`PUT /broadcast` added to `PlaceListController`; `BroadcastListIntegrationTest` (17 tests — auth, permission guard for free user, 3× duplicate 400, limit, order preserved, round-trip, clear) |
| 0.6 | 2026-04-09 | Step 2.5 implemented: `MatchEvent` record, `WsSessionRegistry` stub in `ws/`, `userId` read-only FK on `UserPlaceList`, `MatchingService` real intersection logic (`@Transactional(readOnly=true)`, in-memory set intersection, notify both watcher and broadcaster), `MatchingServiceTest` (11 unit tests — empty list short-circuit, disjoint, single match, multiple names, two watchers partial overlap, symmetric watch dispatch) |
| 0.7 | 2026-04-09 | Step 2.6 implemented: `WsEnvelope<T>` record, `JwtHandshakeInterceptor` (query-param JWT → `JwtService` → `EntitlementService` → 403 on reject), `TransitWebSocketHandler` (register/deregister sessions, ignore inbound), `WsSessionRegistry` updated (`ConcurrentHashMap`, `register`/`deregister`, `sendToAllOpen`), `WsHeartbeatScheduler` (`@Scheduled` 15 s), `WsConfig` (`@EnableWebSocket @EnableScheduling`), `SecurityConfig` updated with `/ws/**` permitAll, `WsAuthIntegrationTest` (5 tests — valid token, missing token, invalid token, expired token, no place permission; all 185 tests green) |
| 0.8 | 2026-04-09 | Step 2.7 implemented: `MatchEvent` moved to `ws/` package, `WsSessionRegistry.sendMatchEvent` real implementation (`ObjectMapper`, `WsEnvelope<MatchEvent>`, skip-on-no-session, evict-on-IOException), `MatchDispatchIntegrationTest` (2 end-to-end tests — broadcast PUT → watcher notified, watch PUT → broadcaster notified; 187 tests total green) |
| 0.9 | 2026-04-09 | Step 2.8 complete: all 187 server tests green; `phase2.http` (auth ×2, watch list, broadcast list, WebSocket connection, 5-step match flow); `http-client.env.json` updated (`wsBaseUrl`, `watchPhone`, `broadcastPhone`) |
| 1.0 | 2026-04-09 | Step 3.1 implemented: `unorm_dart 0.3.2` dependency; `normalizePlaceName` + `validatePlaceName` Dart utilities (4-step pipeline matching server); `place_name_normalizer_test.dart` (17 tests — all 3 PLACE_NAMES.md §5 vectors pass including NFC vector 2; 115 mobile tests green) |
| 1.1 | 2026-04-09 | Step 3.2 implemented: `PlaceValidationError` + `PlaceLimitError` added to `app_error.dart`; `AppErrorInterceptor` (public, maps 400 `VALIDATION_ERROR` → `PlaceValidationError`, 403 `OVER_LIMIT` → `PlaceLimitError`); `PlaceNamesDto`; `PlaceListRepository` (`keepAlive`, 4 methods); `place_list_repository_test.dart` (11 tests — happy path + 5 error-type assertions; 126 mobile tests green) |
| 1.2 | 2026-04-09 | Step 3.3 implemented: `WatchNotifier` (sealed state machine, `add`/`remove`/`save`/`refresh`); `WatchScreen` (add field with normalized preview, Dismissible list, save-error banner, save bar, pull-to-refresh); `/watch` route + permission guard in router; "My Watch List" home-screen entry; `watch_screen_test.dart` (7 widget tests; 133 mobile tests green) |
| 1.3 | 2026-04-09 | Step 3.4 implemented: `BroadcastNotifier` (ordered sealed state, `add`/`remove`/`reorder`/`save`/`refresh`); `BroadcastScreen` (`ReorderableListView` with drag handles, Dismissible, save-error banner, `PlaceLimitError` upgrade message); `/broadcast` route wired to real screen (placeholder removed); `broadcast_screen_test.dart` (5 widget tests); `router_redirect_test.dart` updated with `_EmptyPlaceListRepository` stub (138 mobile tests green) |
| 1.4 | 2026-04-09 | Step 3.5 implemented: `ws_message.dart` (sealed `WsMessage`: `MatchMessage`, `UnknownMessage`); `ws_client.dart` (`@Riverpod(keepAlive: true)` notifier — `connect`/`disconnect`, backoff `min(2s×2^attempt, 60s)`, heartbeat filter, `UnknownMessage` forward-compat, `createChannel` overridable for tests, dispose guard prevents stray timer in `fakeAsync`); `WolehApp.build()` watches `wsClientProvider` for eager init; `web_socket_channel` added; `ws_client_test.dart` (6 unit tests — backoff table, reconnect timing via `fakeAsync`, heartbeat filtered, unknown type emitted, `MatchMessage` fields, backoff reset on receipt; 144 mobile tests green) |

When Phase 2 is complete, update [PRD.md](./PRD.md) phase table to "✅ Complete" and note any deviations (e.g. normalization library chosen for Dart NFC, in-memory vs DB intersection query, final `match` event field names).
