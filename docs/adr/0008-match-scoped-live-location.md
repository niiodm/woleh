# ADR 0008: Match-scoped live location (Phase 4)

## Status

Accepted — implementation in progress ([MAP_LIVE_LOCATION_PLAN.md](../MAP_LIVE_LOCATION_PLAN.md)).

## Context

Woleh may add map UI and device position sharing. Coordinates must **not** replace name-based matching. Peers may only receive another user’s position when both are **currently matched** (non-empty intersection of broadcast vs watch normalized names, same rule as `MatchingService`).

## Decision

- Maintain an in-process **`MatchAdjacencyRegistry`** (`server/.../places/MatchAdjacencyRegistry.java`): bidirectional `userId → matched peer ids`, rebuilt on each successful watch or broadcast list PUT via `PlaceListService`.
- **REST ingest:** `POST /api/v1/me/location` (rate-limited, requires watch or broadcast permission and `users.location_sharing_enabled`). **`PUT /api/v1/me/location-sharing`** toggles the flag. **`GET /api/v1/me`** exposes `profile.locationSharingEnabled`.
- **WebSocket `peer_location`:** on each accepted location POST, `LocationPublishService` sends `WsEnvelope("peer_location", PeerLocationEvent)` to each open session in `MatchAdjacencyRegistry#getCounterparties(publisherId)`.
- **Single JVM v1** is acceptable; multi-instance requires a shared view of adjacency (or recomputation on publish) — align with [0006](0006-rate-limiting-and-scaling.md).

## Consequences

- **Positive:** Fast lookup for location fan-out; adjacency drops automatically when lists diverge.
- **Negative:** Registry state is lost on restart; peers reconnect with no server-side last-known position until lists are saved again or a separate persistence layer is added.
- **Follow-up:** Rate-limited `POST /api/v1/me/location`, sharing toggle, WS types, mobile map — per [MAP_LIVE_LOCATION_PLAN.md](../MAP_LIVE_LOCATION_PLAN.md).
