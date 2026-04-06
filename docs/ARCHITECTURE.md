# Woleh — System Architecture

This document defines the target architecture for **Woleh**, the mobile application and backend in this repository. It is informed by patterns proven in the [bus_finder architecture learnings](./bus_finder-architecture-learnings.md) project (Flutter + Spring Boot, feature slices, JWT + plan gating, WebSocket streaming). Treat this file as the **source of truth** for structural decisions; update it when those decisions change.

## 1. Product context

**Woleh** is a real-time mobility and discovery product: users authenticate, may subscribe to plans that unlock different capabilities, exchange location and intent with the server, and receive live updates over persistent connections. The exact domain (e.g. transit matching, rides, or local discovery) can evolve; the **architectural shape** below stays stable.

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
│  Woleh Mobile   │ ─────────────────────▶│  Woleh API (Spring Boot)     │
│  (Flutter)      │                       │  • Controllers               │
└────────┬────────┘                       │  • Services                  │
         │                                │  • JPA / PostgreSQL         │
         │ WSS (WebSocket)                │  • Security filters         │
         └──────────────────────────────▶│  • Stream registry + WS     │
                                         └──────────────┬───────────────┘
                                                        │
                                                        ▼
                                         ┌──────────────────────────────┐
                                         │  PostgreSQL (+ PostGIS if    │
                                         │  spatial queries are needed)   │
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
- **Maps / location** (if product needs them): e.g. `flutter_map`, `geolocator` — isolate behind `core/location` abstractions.

### 4.2 Directory conventions

- **`lib/core/`** — Network client, interceptors, API base URL / `wsBaseUrl` derivation, error mapping, app-wide constants, logging hooks.
- **`lib/shared/`** — Reusable widgets, layouts, error/empty states.
- **`lib/features/<feature>/`** — Vertical slice:
  - `data/` — API clients, WebSocket datasources, repositories, DTOs.
  - `presentation/` — Screens, widgets, Riverpod providers tied to that feature.
- **`lib/app/`** — `MaterialApp` / router, theme, localization bootstrap.

### 4.3 Routing and access control

- **Centralize** redirect rules in `GoRouter` (auth: unauthenticated users only on public routes; authenticated users skip `/auth/*`).
- **Prefer** `redirect` callbacks (or nested `GoRoute` redirects) for **subscription / plan gates** so protected screens do not mount before the check. Avoid post-frame redirects inside `builder` unless unavoidable.
- Encapsulate “can access feature X” in dedicated providers (e.g. `hasPlanFeatureProvider`) rather than scattering checks in widgets.

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
- **PostgreSQL**; add **PostGIS** only if spatial matching is required.
- **Flyway** (or Liquibase) for schema migrations under `server/src/main/resources/db/migration`.

### 5.2 Layering

- **Controllers** — HTTP mapping, validation (`@Valid`), locale-aware messages if i18n is used; thin: delegate to services.
- **Services** — Business rules, orchestration, transactions.
- **Repositories** — Spring Data interfaces; complex queries in dedicated classes or native queries when needed.
- **Security** — `SecurityFilterChain`: JWT filter, then plan/subscription validation, then rate limiting where applicable.
- **WebSockets** — Config registers paths; **handlers** are thin; **stream services** own session maps, heartbeats, and send helpers.

### 5.3 Security model

- **JWT** for API and WebSocket handshake (`/ws/**` authenticated).
- **Stateless** sessions (`SessionCreationPolicy.STATELESS`).
- **Plan-based authorization** (not only roles): a filter after JWT resolves the user and enforces which routes require which subscription/plan (align with product rules).
- **Public** endpoints: auth, health, webhooks, static assets as needed — listed explicitly in security config.
- **CORS** and **security headers** configured per environment.

### 5.4 Operational guard rails

- **High-frequency writes** (e.g. location): per-user rate limits in controllers or filters; start with in-memory maps for dev, plan **Redis** or gateway limits for multi-instance production.
- **Idempotent mutations**: support `Idempotency-Key` where duplicate submits are costly; persist keys in Redis/DB when scaling out.
- **Global exception handler** — Map domain exceptions to HTTP status and stable JSON error shape (`message`, optional `code`).

### 5.5 Realtime delivery (WebSockets)

- **Handshake**: JWT filter runs before handshake; interceptor copies `userId` (or principal) into WebSocket session attributes.
- **Handler**: On connect, validate identity; on disconnect, unregister.
- **Stream service**: `userId → WebSocketSession`, replace duplicate connections per user, schedule heartbeats, serialize typed payloads into the shared envelope.

### 5.6 Domain logic (e.g. matching)

- Keep **matching** in dedicated services; use **PostGIS** (`ST_DWithin`) for radius queries when applicable.
- **Debouncing** for pair-wise notifications; use in-memory maps for single node, **Redis** for clusters.
- **Cache** route or read models as **DTOs** or projections — avoid `@Cacheable` on raw JPA entities if Redis serialization can break types.

### 5.7 Observability

- Micrometer metrics for critical paths (e.g. matching duration, WS active sessions).
- Structured logs with **correlation IDs** (user id, request id) where possible.
- Actuator health for orchestration.

## 6. API and realtime contracts

### 6.1 REST

- Prefix: `/api/...` (version in path later if needed, e.g. `/api/v1/...`).
- Success envelope (example): `{ "result": "SUCCESS", "message": "...", "data": ... }` — keep consistent with mobile parsers.
- Errors: `{ "result": "ERROR", "message": "..." }` plus appropriate HTTP status.

### 6.2 WebSocket envelope

Standardize on:

```json
{ "type": "heartbeat", "data": "ping" }
{ "type": "<domain_event>", "data": { } }
```

Document each `type` and its `data` schema in `docs/` or OpenAPI companion notes.

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

When a decision is non-obvious or costly to reverse (e.g. broker vs in-process streams, payment provider), add a short **Architecture Decision Record** under `docs/adr/` with context, decision, and consequences.

## 10. Related documents

- [Product Requirements (PRD)](./PRD.md) — what Woleh builds and why.
- [bus_finder architecture learnings](./bus_finder-architecture-learnings.md) — rationale and anti-patterns from the reference project.

---

**Document owner**: maintainers of the Woleh repo.  
**Last updated**: 2026-04-06
