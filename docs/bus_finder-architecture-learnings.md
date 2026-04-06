# bus_finder — structure & architecture learnings

This document summarizes key project-structure and architecture choices in `/Users/morgan/Workspace/bus_finder` and extracts reusable patterns for a similar app in this repository.

## Repo shape (high level)

`bus_finder` is a mono-repo with two primary applications:

- **`mobile/`**: Flutter app (Dart)
- **`server/`**: Spring Boot app (Java 17)

It also contains a large set of design/phase documents at the repo root (e.g. `DESIGN.md`, `PHASE*_PLAN.md`, `PHASE*_ARCHITECTURE.md`), which appear to be used as an execution log and as cross-links to implementation locations.

## Mobile app (`mobile/`) architecture

### Dependency choices (signals from `pubspec.yaml`)

Mobile uses a fairly standard “modern Flutter app stack”:

- **Navigation**: `go_router`
- **State management**: `flutter_riverpod` + generators (`riverpod_generator`, `riverpod_annotation`)
- **HTTP**: `dio` + `retrofit` + codegen (`retrofit_generator`)
- **Modeling**: `freezed` + `json_serializable`
- **Storage**: `flutter_secure_storage` (JWT/token), `shared_preferences`
- **Realtime**: `web_socket_channel`
- **Maps + geo**: `flutter_map` (OpenStreetMap), `geolocator`, `latlong2`
- **Testing**: `flutter_test` + `mockito`

This combination implies:

- **Typed API surface** via Retrofit + generated DTOs
- **Predictable state graph** via Riverpod, with testable notifiers/providers
- **Clean-ish separation** between “data sources” (HTTP/WS), “models”, “providers”, and UI

### Project organization (feature-based)

From file locations like:

- `mobile/lib/features/passenger/...`
- `mobile/lib/features/driver/...`
- `mobile/lib/features/auth/...`
- `mobile/lib/features/subscription/...`
- `mobile/lib/core/...`
- `mobile/lib/shared/...`
- `mobile/lib/app/routes/app_router.dart`

…the app is structured as:

- **`core/`**: cross-cutting infrastructure (networking, constants, errors, location sources)
- **`shared/`**: shared widgets/utilities
- **`features/<domain>/`**: vertical slices by product area, typically with:
  - **`data/`**: DTOs, clients/datasources (HTTP/WS), repository impls
  - **`presentation/`**: screens/widgets and Riverpod providers/notifiers

This is a good fit for apps where driver/passenger flows are large and evolving independently.

### Routing + guards (auth + subscription)

Routing is centralized in `mobile/lib/app/routes/app_router.dart` using `GoRouter` and Riverpod state:

- **Auth redirect**: if unauthenticated and not on `/auth/*`, redirect to `/auth/phone`
- **Prevent back into auth flow**: if authenticated and on `/auth/*`, redirect to `/home`
- **Feature gating**: per-route checks for subscription (driver vs passenger)
  - Guard logic reads Riverpod providers like `hasDriverSubscriptionProvider` / `hasPassengerSubscriptionProvider`

Notable nuance: some subscription “guards” are implemented inside `builder` with a post-frame redirect. For a new app, consider moving these guards into `redirect` (or route-level redirect) so unauthorized screens never build.

### Networking + consistent error mapping

`mobile/lib/core/network/error_interceptor.dart` maps `DioException` to a set of custom app exceptions (401/403/404/429/5xx etc). The benefit is a single “translation layer” between backend response shape and UI error handling.

If you reuse this pattern:

- Keep **backend error schema stable** (a predictable `message` field is assumed).
- Ensure **domain-specific error types** are distinct (e.g., subscription-required vs general forbidden).

### Environment configuration (base URLs + WS URLs)

`mobile/lib/core/constants/api_constants.dart`:

- Uses `--dart-define=API_BASE_URL=...` for switching environments.
- Derives a `wsBaseUrl` from the API base URL (http→ws, https→wss).
- Keeps WebSocket paths in constants (`/ws/passenger/buses`, `/ws/driver/passengers`).

This is an effective “single source of truth” for endpoints and reduces drift between REST and WS URLs.

### Realtime streaming on mobile (WebSockets with typed messages)

Despite class names like `*SseClient`, the implementations shown are WebSocket clients:

- `PassengerBusesSseClientImpl` connects to `${wsBaseUrl}/ws/passenger/buses`
- `PassengersSseClientImpl` connects to `${wsBaseUrl}/ws/driver/passengers`
- Messages are JSON envelopes with a `type` field (`heartbeat`, `bus`, `passenger`) and a `data` payload.

The client:

- Filters heartbeats.
- Parses `data` into typed models.
- Uses a `StreamController` per connection for consumption by Riverpod providers.

For reuse, consider standardizing:

- Message envelope schema (`{ type, data }`) across all streams
- Heartbeat behavior (interval, payload), and client-side timeouts/reconnect

## Server app (`server/`) architecture

### Technology and layering

Server is Spring Boot with a conventional layering:

- **Controllers** (`server/src/main/java/.../controller/*Controller.java`)
- **Services** (`.../service/...`)
- **Repositories** (`.../repository/...`) via Spring Data JPA
- **Security** (`.../security/...`) via filter chain + JWT
- **WebSockets** (`.../websocket/...`) via Spring WebSocket handlers/config

`BusFinderServerApplication.java` enables JPA repositories, entity scanning, and scheduling (`@EnableScheduling`), hinting at periodic jobs (e.g., cleanup, subscription checks, or scheduled tasks).

### Security model: JWT + “plan-based authorization”

`SecurityConfig.java` shows:

- Stateless JWT auth (`SessionCreationPolicy.STATELESS`)
- `JwtAuthenticationFilter` to populate auth
- `SubscriptionValidationFilter` to enforce access based on subscription plan type (driver/passenger)
- `RateLimitingFilter` in the chain after subscription validation
- Static resources and auth endpoints are public
- WS handshake endpoints (`/ws/**`) are authenticated

This is a noteworthy choice: **authorization is not purely role-based**; it’s enforced by subscription state/plan type. That’s a good fit when monetization gates features and a user may need to “upgrade” without changing identity.

### Controllers: request-level guard rails

Both `PassengerController` and `DriverController` include lightweight safeguards that are easy to copy:

- **In-memory rate limiting**: per-user “last publish timestamp” to enforce ~1 update/sec for location publishing.
- **Idempotency key** (driver route start): a simplistic in-memory idempotency window using an `Idempotency-Key` header.

These are pragmatic guard rails for early stages, but note the trade-offs:

- They **won’t work across multiple server instances** (not shared), and reset on deploy.
- For production, move these to something shared (Redis) or use an API gateway / dedicated rate limiting.

### Realtime streaming on server: WebSockets + session registry + heartbeats

`WebSocketConfig.java` registers handlers:

- `/ws/passenger/buses`
- `/ws/driver/passengers`
- `/ws/admin/spoof/drivers`

Each endpoint attaches a `JwtHandshakeInterceptor`.

The interceptor (`JwtHandshakeInterceptor.java`) copies the authenticated principal into WebSocket session attributes so handlers can associate a connection with a `userId`.

The streaming service pattern is:

- WebSocket handler validates `userId` on connect and registers the session.
- A stream service (e.g. `PassengerBusesStreamService`) stores `passengerId -> WebSocketSession` in a concurrent map, and:
  - Replaces existing connections for that user
  - Schedules a **heartbeat** (15s) and sends `type=heartbeat` messages
  - Sends typed domain events wrapped as WS messages (`type=bus`, `type=passenger`)

This is a clean, testable structure because:

- Handlers are thin (lifecycle + identity).
- Stream services own the session registry and message serialization.

### Matching service: PostGIS spatial queries + debouncing + caching

`GeospatialMatchingService.java` is a good example of evolving from “mock matching” to a scalable approach:

- **Spatial filtering**: PostGIS `ST_DWithin` queries via repositories to find nearby drivers/passengers within a configurable radius.
- **Stop-based matching**: intersects passenger searched stops with driver route stops.
- **Debouncing**: in-memory `driverId:passengerId -> lastSent` timestamps to avoid noisy updates.
- **Caching**: route data cached (`@Cacheable("routes")`), with explicit conversion logic to handle Redis deserialization returning `LinkedHashMap` instead of a typed `Route`.
- **Performance instrumentation**: uses Micrometer `Timer` to measure matching duration.
- **Notification hooks**: optional `NotificationHelperService` called for “bus approaching” or “passenger waiting”.

The Redis cache deserialization workaround is a key lesson: when caching complex JPA entities, you need either:

- A safe serialization strategy (DTO-based caching, or a configured serializer), or
- Defensive conversion logic like this project has (works, but adds complexity).

### Documentation + delivery workflow as part of architecture

`bus_finder` treats documentation as a first-class artifact:

- Root-level design docs cross-link into specific code paths.
- The server has `.http` collections (`server/api-tests/*.http`) to run end-to-end API flows inside the IDE, with variable chaining and assertions.

This dramatically reduces “tribal knowledge” and speeds up onboarding/testing.

## Reusable patterns to bring into this project

### 1) Adopt the same “feature vertical slices” (mobile/front-end)

- `core/` for cross-cutting infrastructure
- `shared/` for reusable UI/components
- `features/<domain>/data` + `features/<domain>/presentation`

This scales well as driver/passenger (or analogous) flows diverge.

### 2) Centralize routing and gate access in one place

- Keep auth redirect rules in one router file.
- Prefer route-level redirects/guards over post-frame redirects in builders.
- Encode subscription/plan gating as a dedicated concept (not scattered booleans).

### 3) Standardize realtime message envelopes

Use the same schema everywhere:

- Envelope: `{ "type": "...", "data": ... }`
- Heartbeat: `type=heartbeat` with a stable payload
- Domain events: `type=bus`, `type=passenger` (or your domain equivalents)

This makes client parsing trivial and consistent.

### 4) Copy the “thin handler + stream service” WebSocket pattern

It keeps responsibilities crisp:

- Handler: connection lifecycle + identity extraction
- Stream service: session registry + message send + heartbeat scheduling

### 5) Keep early guard rails, but plan the “distributed” upgrade path

Reusing the in-memory rate-limit/idempotency approach is fine to start, but document the migration path:

- Rate limiting: Redis token bucket / gateway limits
- Idempotency: persistent idempotency keys (Redis/DB) with TTL
- Debouncing: shared store if horizontally scaled

### 6) Avoid caching JPA entities directly

If you need caching, prefer:

- Cache DTOs / primitive projections, or
- Use `@Cacheable` with a serializer that preserves types, and test it in integration.

The “LinkedHashMap from Redis” workaround works but is a code smell you can avoid up front.

### 7) Treat `.http` collections as part of the architecture

The IDE-run `.http` collections with assertions are low-cost and high-leverage. They are also an excellent “contract surface” for a mobile client team.

## Concrete “starter template” recommendations for your similar app

If you want your new app to inherit the strongest parts of `bus_finder`, aim for:

- **Shared message envelope + typed DTOs** across REST + WS.
- **Single router** with auth + plan gates.
- **A `core/network/` layer** with:
  - A single HTTP client
  - A single error mapping layer (like the Dio interceptor)
  - Environment-based base URLs (like `--dart-define`)
- **A backend WS streaming layer** that mirrors the handler/service split.
- **IDE runnable API collections** from day one.

## Files used as primary evidence

Mobile:

- `mobile/pubspec.yaml`
- `mobile/lib/app/routes/app_router.dart`
- `mobile/lib/core/network/error_interceptor.dart`
- `mobile/lib/core/constants/api_constants.dart`
- `mobile/lib/features/passenger/data/datasources/buses_sse_client.dart`
- `mobile/lib/features/driver/data/datasources/passengers_sse_client.dart`

Server:

- `server/src/main/java/odm/busfinder/server/config/SecurityConfig.java`
- `server/src/main/java/odm/busfinder/server/config/WebSocketConfig.java`
- `server/src/main/java/odm/busfinder/server/websocket/JwtHandshakeInterceptor.java`
- `server/src/main/java/odm/busfinder/server/websocket/PassengerBusesWebSocketHandler.java`
- `server/src/main/java/odm/busfinder/server/service/streaming/PassengerBusesStreamService.java`
- `server/src/main/java/odm/busfinder/server/service/matching/GeospatialMatchingService.java`
- `server/api-tests/README.md`
- `DESIGN.md`

