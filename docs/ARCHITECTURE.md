# Woleh — System Architecture

This document defines the target architecture for **Woleh** (the **transit** mobile app) and the **general-purpose** backend API in this repository. It is informed by patterns proven in the [bus_finder architecture learnings](./bus_finder-architecture-learnings.md) project (Flutter + Spring Boot, feature slices, JWT + plan gating, WebSocket streaming). Treat this file as the **source of truth** for structural decisions; update it when those decisions change.

**Intentional divergence from bus_finder:** Woleh does **not** model separate **passenger** vs **driver** (or similar) user types in code or product identity. There is a single **user**; what they may do is determined by **permissions** attached to their active subscription (see §5.3). The mobile app uses that permission list to show or hide UI; the server **must** enforce the same permissions on every API and WebSocket capability.

**Place names, not route objects:** Woleh does **not** persist rich **route** entities (ordered stops with coordinates, geometry, etc.) as in bus_finder. The domain uses **lists of place names** only: users who may **broadcast** list the names of places they will drive through; users who may **watch** list the names of places they want to see buses for. **No latitude/longitude** is stored on these names—matching is **string-based** (see §5.6). **Normalization** for comparison is defined in [PLACE_NAMES.md](./PLACE_NAMES.md) (v1 baseline: trim → NFC → case fold → collapse internal whitespace).

## 1. Product context

### 1.1 Woleh (transit) vs platform (backend)

**Woleh**—the mobile experience and user-facing **copy** in this repo—is a **transit** product: it helps riders and vehicle operators coordinate using **place names** along a path (stops, junctions, terminals—whatever naming people use) and live updates. Marketing, UI strings, and app store positioning should **read as transit**, not generic “discovery.”

The **backend** (Spring Boot API, permissions, place-name matching, WebSockets) is intentionally **general-purpose**: it follows patterns that also suit **hyperlocal discovery** and other place-name–driven apps, so you can **reuse** the same server for a different client or product later without a rewrite. In code, prefer **neutral** names for modules and packages (`places`, `streams`, `matching`) where it does not obscure Woleh; avoid hard-coding “bus” or “transit” into **core** server types unless the rule is truly transit-only. **Transit-specific language belongs in** the Flutter app, API documentation aimed at Woleh consumers, and permission catalog copy—not necessarily in every class name.

**Woleh** is a real-time **transit** product built on that platform: users authenticate, may subscribe to plans that grant a **set of permissions** (capabilities), submit **place-name lists** according to those permissions, and receive live updates over persistent connections.

**Goals**

- Clear separation between mobile client, API, and realtime delivery.
- Security and monetization (plan-based access) enforced consistently on the server.
- Testable, observable services with contracts that client and server teams can share.

**Non-goals (for this document)**

- Detailed UI specification or marketing copy.
- Vendor lock-in to a single payment or maps provider (integrate behind interfaces).

## 2. High-level system view

```
┌─────────────────┐     HTTPS (REST)      ┌──────────────────────────────┐
│  Woleh Mobile   │ ─────────────────────▶│  API (Spring Boot)           │
│  (transit UX)   │                       │  general-purpose core        │
└────────┬────────┘                       │  • Controllers / services    │
         │                                │  • JPA / PostgreSQL          │
         │ WSS (WebSocket)                │  • Security / permissions  │
         └──────────────────────────────▶│  • WebSockets / streams      │
                                         └──────────────┬───────────────┘
                                                        │
                                                        ▼
                                         ┌──────────────────────────────┐
                                         │  PostgreSQL                  │
                                         │  (PostGIS only if a future   │
                                         │   feature needs spatial data)  │
                                         └──────────────────────────────┘
```

Optional components (add when needed, not required on day one):

- **Redis**: shared rate limits, idempotency caches, or **DTO-only** caching (avoid caching JPA entities directly).
- **Message broker**: if async pipelines or fan-out exceed in-process delivery.
- **Push (FCM/APNs)**: notifications triggered from domain services after matches or events.

## 3. Repository layout

Recommended mono-repo structure (aligns with bus_finder learnings):

| Path | Purpose |
|------|---------|
| `mobile/` | Flutter app: `lib/core`, `lib/shared`, `lib/features/<domain>`, `lib/app` (router, bootstrap) |
| `server/` | Spring Boot: `controller`, `service`, `repository`, `security`, `websocket`, `config` |
| `server/api-tests/` | IDE-runnable `.http` collections + env files (contract tests for humans and CI) |
| `docs/` | Architecture, ADRs, integration notes |

Keep **design notes and phase logs** in `docs/` when they help onboarding; cross-link from code where useful.

## 4. Mobile architecture (Flutter)

### 4.1 Stack (recommended)

- **Navigation**: `go_router` — single `routerProvider` with auth and plan-aware redirects.
- **State**: `flutter_riverpod` + codegen for providers/notifiers.
- **HTTP**: `dio` + `retrofit` (or equivalent) with generated clients for typed REST.
- **Models**: `freezed` / `json_serializable` (or equivalent immutable DTOs).
- **Secrets**: `flutter_secure_storage` for tokens; `shared_preferences` for non-sensitive prefs.
- **Realtime**: `web_socket_channel` (or equivalent) consuming a **standard envelope** (see §6).
- **Maps / live GPS** (optional, not required for core place-name lists): if added later, isolate behind `core/location` abstractions. Core matching does **not** rely on coordinates attached to place names.

### 4.2 Directory conventions

- **`lib/core/`** — Network client, interceptors, API base URL / `wsBaseUrl` derivation, error mapping, app-wide constants, logging hooks.
- **`lib/shared/`** — Reusable widgets, layouts, error/empty states.
- **`lib/features/<feature>/`** — Vertical slice:
  - `data/` — API clients, WebSocket datasources, repositories, DTOs.
  - `presentation/` — Screens, widgets, Riverpod providers tied to that feature.
- **`lib/app/`** — `MaterialApp` / router, theme, localization bootstrap.

### 4.3 Routing and access control

- **Centralize** redirect rules in `GoRouter` (auth: unauthenticated users only on public routes; authenticated users skip `/auth/*`).
- **Prefer** `redirect` callbacks (or nested `GoRoute` redirects) for **permission gates** (capabilities required for a route) so protected screens do not mount before the check. Avoid post-frame redirects inside `builder` unless unavoidable.
- **Permissions drive UI**: after auth, the client loads the user’s effective **permission set** from the subscription/session API (see §5.3). Use small, testable providers such as `permissionProvider` / `hasPermission('perm.stream_live_updates')` (exact string constants shared with server) to:
  - show or hide navigation entries, buttons, and panels;
  - choose which realtime streams to subscribe to.
- **Do not** encode parallel “role” trees (e.g. driver vs passenger folders) unless a feature is truly unrelated; prefer feature slices that check permissions at the boundary.

### 4.4 Networking

- One **Dio** instance with interceptors:
  - Attach `Authorization: Bearer <token>` when present.
  - **Error interceptor** maps HTTP status and body `message` to typed app exceptions (400/401/403/404/429/5xx) for consistent UI handling.
- **Environment**: `--dart-define=API_BASE_URL=...` for dev/staging/prod; derive `ws` / `wss` from the same base URL to avoid drift.

### 4.5 Realtime client

- Parse JSON envelopes: `{ "type": string, "data": ... }`.
- Ignore or handle `type: "heartbeat"` without surfacing to UI.
- Map domain `type` values to typed models; expose `Stream` or `AsyncNotifier` to UI.
- Document reconnect/backoff policy in code or `docs/` (exponential backoff is a good default).

## 5. Server architecture (Spring Boot)

### 5.1 Stack (recommended)

- **Java 17+**, **Spring Boot 3.x**, Spring Web, Spring Security, Spring Data JPA.
- **PostgreSQL**. **PostGIS is not required** for the core Woleh model (name-only place matching). Add it only if a future feature needs geospatial queries.
- **Flyway** (or Liquibase) for schema migrations under `server/src/main/resources/db/migration`.

### 5.2 Layering

- **Controllers** — HTTP mapping, validation (`@Valid`), locale-aware messages if i18n is used; thin: delegate to services.
- **Services** — Business rules, orchestration, transactions.
- **Repositories** — Spring Data interfaces; complex queries in dedicated classes or native queries when needed.
- **Security** — `SecurityFilterChain`: JWT filter, then **permission** validation (from active subscription), then rate limiting where applicable.
- **WebSockets** — Config registers paths; **handlers** are thin; **stream services** own session maps, heartbeats, and send helpers.

### 5.3 Security model

- **JWT** for API and WebSocket handshake (`/ws/**` authenticated).
- **Stateless** sessions (`SessionCreationPolicy.STATELESS`).
- **Permission-based authorization** (not passenger/driver types, not coarse roles only):
  - Each **subscription plan** defines a set of **permission strings**. The **v1 catalog** for Woleh is in [PRD.md](./PRD.md) §13.1 (e.g. `woleh.place.watch`, `woleh.place.broadcast`).
  - The user’s **active subscription** yields an **effective permission set** (union of plan permissions, minus revocations if any).
  - After JWT validation, a filter or method-level checks assert the required permission(s) for the route or operation. WebSocket paths and message handlers enforce the same permissions as the REST surface for equivalent capabilities.
  - **Server is authoritative**: the client uses permissions only for UX; never rely on UI hiding alone for security.
- **Public** endpoints: auth, health, webhooks, plan catalog (if public), static assets as needed — listed explicitly in security config.
- **CORS** and **security headers** configured per environment.

**API contract (illustrative):** responses that describe the current entitlements should include a stable list, e.g. `data.permissions: string[]` (or named roles document in OpenAPI). Keep permission strings in a **single shared catalog** (codegen or OpenAPI) to avoid drift between mobile and server.

### 5.4 Operational guard rails

- **High-frequency writes** (e.g. updating place lists or optional live telemetry if introduced later): per-user rate limits in controllers or filters; start with in-memory maps for dev, plan **Redis** or gateway limits for multi-instance production.
- **Idempotent mutations**: support `Idempotency-Key` where duplicate submits are costly; persist keys in Redis/DB when scaling out.
- **Global exception handler** — Map domain exceptions to HTTP status and stable JSON error shape (`message`, optional `code`).

### 5.5 Realtime delivery (WebSockets)

- **Handshake**: JWT filter runs before handshake; interceptor copies `userId` (or principal) into WebSocket session attributes.
- **Handler**: On connect, validate identity; on disconnect, unregister.
- **Stream service**: `userId → WebSocketSession`, replace duplicate connections per user, schedule heartbeats, serialize typed payloads into the shared envelope.

### 5.6 Domain logic: place-name lists and matching

- **No route aggregate**: Do not model bus_finder-style **Route** / **RouteStop** entities with coordinates. Persist only what is needed for two concepts (exact API names TBD):
  - **Broadcast path** — ordered or unordered **list of place name strings** for “places I will drive through” (permission-gated).
  - **Watch list** — **list of place name strings** for “places I want to see buses for” (permission-gated).
- **Matching**: Determine relevance by **comparing place names as strings** after normalization ([PLACE_NAMES.md](./PLACE_NAMES.md)). **v1 rule** (ordered broadcast vs unordered watch, intersection): [PRD.md](./PRD.md) §13.2. **Do not** attach lat/long to place names in storage for this purpose.
- **Normalization**: Implement `normalizePlaceName` per [PLACE_NAMES.md](./PLACE_NAMES.md). Server and mobile must share the same algorithm and test vectors; optional alias/fuzzy rules require a doc version bump.
- **Debouncing** for high-frequency notifications still applies where users receive live updates; use in-memory maps for single node, **Redis** for clusters if scaled horizontally.
- **Caching**: Prefer caching **DTOs** (e.g. resolved permission sets, denormalized watch lists for read paths) — avoid `@Cacheable` on raw JPA entities if Redis serialization can break types.

### 5.7 Observability

- Micrometer metrics for critical paths (e.g. name-match evaluation duration, WS active sessions).
- Structured logs with **correlation IDs** (user id, request id) where possible.
- Actuator health for orchestration.

## 6. API and realtime contracts

The **v1 contract** (paths, envelopes, permission matrix, WebSocket outline) lives in [API_CONTRACT.md](./API_CONTRACT.md). Summaries below stay aligned with that file.

### 6.1 REST

- Prefix: **`/api/v1`** for v1 (see [API_CONTRACT.md](./API_CONTRACT.md)).
- Success envelope: `{ "result": "SUCCESS", "message": "...", "data": ... }` — keep consistent with mobile parsers.
- Errors: `{ "result": "ERROR", "message": "..." }` plus appropriate HTTP status.
- **Place lists**: JSON arrays of place name strings—no coordinate fields on those names for the core model (see §5.6).

### 6.2 WebSocket envelope

Standardize on:

```json
{ "type": "heartbeat", "data": "ping" }
{ "type": "<domain_event>", "data": { } }
```

Event types and handshake auth: [API_CONTRACT.md](./API_CONTRACT.md) §8.

## 7. Testing strategy

| Layer | Approach |
|-------|----------|
| Mobile | Widget tests with `ProviderScope` overrides; unit tests for notifiers; integration tests for critical flows |
| Server | JUnit 5 for services; `@SpringBootTest` for controllers; Testcontainers for DB if integration tests justify it |
| Contract | `server/api-tests/*.http` with environments and assertions; optional schema checks in CI |

## 8. CI/CD and environments

- **Dev**: local DB + optional Docker Compose; `API_BASE_URL` pointing at host or tunnel.
- **Staging / prod**: secrets via environment or secret manager; TLS everywhere; WebSocket over `wss://`.
- Mobile: Fastlane or similar for beta distribution when ready; align Firebase (or chosen) config per flavor.

## 9. Evolution and ADRs

Recorded decisions live under [docs/adr/README.md](./adr/README.md) (WebSocket auth, OTP policy, Ghana jurisdiction, WebView payment, scaling, tenancy). Add a new ADR when a choice is non-obvious or costly to reverse (e.g. second product on the same API).

## 10. Related documents

- [Product Requirements (PRD)](./PRD.md) — what Woleh builds and why.
- [API & permission contract](./API_CONTRACT.md) — REST v1, permission matrix, WebSockets.
- [Architecture Decision Records (ADRs)](./adr/README.md) — recorded choices (e.g. payment WebView, Ghana, OTP).
- [Place name normalization](./PLACE_NAMES.md) — canonical matching rules for place strings.
- [bus_finder architecture learnings](./bus_finder-architecture-learnings.md) — rationale and anti-patterns from the reference project.

---

**Document owner**: maintainers of the Woleh repo.  
**Last updated**: 2026-04-06 ([ADRs](./adr/README.md); [API_CONTRACT.md](./API_CONTRACT.md) v1.2)
