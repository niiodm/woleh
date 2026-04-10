# Plan: Map view and live location updates (match-scoped)

This document plans **optional** map and GPS telemetry for Woleh. It is **additive** to name-only matching ([PRD.md](./PRD.md) §7.4–7.5, [ARCHITECTURE.md](./ARCHITECTURE.md) §4.1, §5.6): coordinates are **not** attached to place names and do **not** affect matching.

**Hard product rule:** A user’s position is **only** ingested by the server and **only** delivered to peers who are **currently matched**—defined as having **non-empty intersection** of normalized place names between one party’s **broadcast** list and the other’s **watch** list (same rule as today’s [`MatchingService`](../server/src/main/java/odm/clarity/woleh/places/MatchingService.java)).

**Suggested phase:** Treat as **Phase 4** (or a named epic) once approved; update [PRD.md](./PRD.md) §10 when committed.

---

## 1. Goals and non-goals

### 1.1 Goals

- **G1 — Map UX:** Show the user’s position and **matched peers’** last known positions on a map (Flutter), with updates driven by WebSocket messages.
- **G2 — Privacy:** No location REST ingest or WS delivery except for users who are **matched** at the time of the operation; peers never see location without an active name intersection.
- **G3 — Control:** User can **stop** sharing from the app; server stops accepting and forwarding for that user ([PRD](./PRD.md) FR-L2).
- **G4 — Abuse resistance:** Server-side rate limits on publish ([PRD](./PRD.md) FR-L3, existing patterns in Phase 3).
- **G5 — Degraded realtime:** If WS drops, client shows stale state + reconnect path ([ARCHITECTURE.md](./ARCHITECTURE.md) NFR-2).

### 1.2 Non-goals (initial delivery)

- Using coordinates for **matching** or **place name** storage.
- **PostGIS** or spatial indexes (not required to ship v1).
- **Background** tracking beyond product-defined foreground use ([PRD](./PRD.md) FR-L1); document exact OS behavior in an ADR.
- Historical **trails** or long retention of precise coordinates (default: **last point only** in memory/short TTL unless ADR extends retention).

---

## 2. Privacy and security principles

| Principle | Implementation sketch |
|-----------|------------------------|
| **Match-only recipients** | Before accepting `POST` location or forwarding over WS, server evaluates **current** match adjacency between publisher and target (see §3). |
| **Least data** | Payload: lat, lng, optional accuracy, heading/speed if needed, `recordedAt` (device time) or server `receivedAt`. No raw place lists in location messages. |
| **Revocation on list change** | When either user’s broadcast or watch list is updated, recompute adjacency; **remove** edges that no longer intersect; **stop** forwarding; optionally emit a small WS `type` so clients drop markers immediately (see §4.2). |
| **Permissions** | Reuse existing capabilities (e.g. `woleh.place.broadcast` / `woleh.place.watch`); only users who may participate in matching may opt into location sharing (exact matrix in ADR). |
| **Audit / retention** | Document whether coordinates are logged (default: **no** full precision in application logs). |

Add **[ADR 00xx]: Match-scoped live location** when implementation starts; reference FR-L1–L3 and this plan.

---

## 3. Server design

### 3.1 Match adjacency (authoritative for “who may see whom”)

Today, matches are **computed on list save** and pushed as ephemeral `match` WS events; there is **no** persistent “match pair” table.

For location, the server needs a **fast, consistent** answer to: *“Is user A matched to user B right now?”*

**Recommended approach (v1):**

**Implementation status:** `MatchAdjacencyRegistry` + `PlaceListService` hook + unit tests are **done** (`server/.../places/MatchAdjacencyRegistry.java`). REST publish, WS `peer_location`, and mobile map are **not** started.

1. **`MatchAdjacencyRegistry` (in-process component)**  
   - Maintains `Map<Long userId, Set<Long> counterparties>` (bidirectional: if A is in B’s set, B is in A’s).  
   - **Update** whenever [`MatchingService`](../server/src/main/java/odm/clarity/woleh/places/MatchingService.java) finds intersections: on each `dispatchBroadcastMatches` / `dispatchWatchMatches`, merge in new pairs for the users involved.  
   - **Rebuild or diff** for affected users when a place list **PUT** completes: safest v1 is to **recompute** that user’s counterparties by re-running the same intersection logic used by `MatchingService` for that user only (O(number of opposite lists))—or invalidate and lazy-rebuild on first location publish.

2. **Consistency rule**  
   - Before **forwarding** a location update from `publisherId` to `targetId`, assert `targetId ∈ adjacency.get(publisherId)` **and** optionally re-check one intersection of normalized names (defense in depth against stale adjacency).

3. **List change**  
   - After `PlaceListService` saves a list, refresh adjacency for the owning user (and all former counterparties if doing incremental fixups). Anyone who **drops out** of match no longer receives forwards.

**Multi-instance note:** In-memory adjacency is wrong across nodes. Document **Phase 4 v1** as single-node or sticky sessions; **ADR** for Redis/pub-sub or shared store before horizontal scale.

### 3.2 REST: publish location (authenticated)

**Implementation status:** `POST /api/v1/me/location`, `PUT /api/v1/me/location-sharing`, `LocationPublishService`, `LocationPublishRateLimiter`, Flyway `V8__user_location_sharing.sql`, `GET /me` profile field `locationSharingEnabled` — **done**. WebSocket fan-out is §3.3.

- **Endpoint:** `POST /api/v1/me/location` — documented in [API_CONTRACT.md](./API_CONTRACT.md) §6.4.1.
- **Body:** `{ "latitude", "longitude", "accuracyMeters?", "heading?", "speed?", "recordedAt" }` (ISO-8601).
- **Behavior:**  
  - If user has **disabled** sharing (flag in DB or session—see §3.4), return **204** or **403** per ADR.  
  - Validate ranges; apply **per-user rate limit** (e.g.1 req / second, align with bus_finder-style guard rails in [bus_finder-architecture-learnings.md](./bus_finder-architecture-learnings.md)).  
  - If user has **no** current counterparty, accept but **no fan-out** (or204—product choice; prefer accept+no-op to simplify client).

### 3.3 WebSocket: fan-out to matched peers only

- **Transport:** Existing path [`/ws/v1/transit`](../server/src/main/java/odm/clarity/woleh/ws/) and envelope [`WsEnvelope`](../server/src/main/java/odm/clarity/woleh/ws/WsEnvelope.java) pattern.
- **New message `type` (example):** `peer_location`  
  - **data:** `{ "userId": "<publisher string id>", "latitude", "longitude", "accuracyMeters?", "receivedAt": "<instant>" }`  
  - **Recipients:** Each `counterpartyId` in adjacency for `publisherId` with an **open** session in [`WsSessionRegistry`](../server/src/main/java/odm/clarity/woleh/ws/WsSessionRegistry.java). **Do not** send publisher’s own message back as `peer_location` (they use local GPS).

**Debouncing:** Optional server-side dedupe (e.g. min interval per `publisherId→targetId`) to limit noise; mirrors bus_finder matching debounce philosophy.

### 3.4 Stopping sharing

**Implementation status:** `PUT /api/v1/me/location-sharing` with `{ "enabled": false }` (same endpoint for on/off). `DELETE` is not used in v1.

- **Client:** Set `enabled` to `false` via `PUT /api/v1/me/location-sharing`.  
- **Server:** Persist flag; **reject** further `POST /me/location` with **403** `LOCATION_SHARING_OFF` until re-enabled.

### 3.5 Testing

- **Unit:** Adjacency update/removal on list changes; publish rejected when unmatched; forward only to matched peers.  
- **Integration:** Two users with intersecting lists; A publishes; B receives `peer_location` on WS; after A removes overlapping names, B stops receiving (and/or receives `match_ended`—see §4.2).  
- **`.http`:** Add scenarios under `server/api-tests/` for publish + WS capture (or extend existing WS tests).

---

## 4. Mobile design (Flutter)

### 4.1 Dependencies and layering

- Add **`flutter_map`** + **`latlong2`** (OSM tiles, aligned with [bus_finder-architecture-learnings.md](./bus_finder-architecture-learnings.md)); add **`geolocator`** (or existing abstraction) under **`lib/core/location/`** per [ARCHITECTURE.md](./ARCHITECTURE.md) §4.1.
- **Do not** put map widgets in `core/`; keep **`lib/features/<feature>/presentation/`** for screens.

### 4.2 WebSocket client

- Extend [`WsMessage`](../mobile/lib/core/ws_message.dart) parsing with **`PeerLocationMessage`** (and optionally **`MatchEndedMessage`** / reuse `MatchMessage` + explicit revoke—product choice).  
- Maintain **`Map<String userId, PeerLocation>`** (last fix per peer) in a **`StateNotifier`**; drop entry on revoke or when user turns sharing off.

### 4.3 Location publish notifier

- Foreground **`StreamSubscription`** on position updates; **throttle** to server limit; call `POST /api/v1/me/location` when sharing is on and user has applicable permission.  
- On app backgrounding, **pause** or stop per FR-L1 ADR.

### 4.4 Map screen

- Reusable **`LocationMap`**-style widget (markers + OSM) modeled on bus_finder’s `mobile/lib/shared/widgets/location_map.dart` pattern: **self** marker from local source; **peers** from WS-derived map.  
- Entry points: e.g. from home after a match, or a “Live map” route gated by permission.  
- **Empty / unmatched:** Explain that the map shows peers only when names match.

### 4.5 Testing

- Widget tests with fake peer location state; WS parsing tests for new types.

---

## 5. Documentation and API contract

| Artifact | Action |
|----------|--------|
| [API_CONTRACT.md](./API_CONTRACT.md) | Add location publish + sharing toggle; WS `type` values. |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | **§5.8** match-scoped live location; **§4.1** map stack; **§6.2** note on `peer_location`. |
| [PRD.md](./PRD.md) | §7.5 match-scoped sharing rule, **FR-L4**, Phase 4 in §10, executive summary (v0.18). |
| New ADR | [0008-match-scoped-live-location.md](./adr/0008-match-scoped-live-location.md) |

---

## 6. Rollout

- **Feature flag** (server + mobile) until privacy copy and OS permissions are reviewed.  
- Staging **dogfood** with two test accounts and overlapping lists.  
- Metrics: publish rate, WS fan-out count, rate-limit hits, adjacency size (gauges).

---

## 7. Open decisions (resolve in ADR or design review)

1. **Stale adjacency:** Strict re-check of name intersection on every publish vs. trust registry only.  
2. **Explicit WS “revoke”** vs. silent stop + client TTL for peer markers.  
3. **Unmatched publish:** 204 no-op vs. 403 when zero counterparties.  
4. **Permission matrix:** Must user have both broadcast and watch to see map, or only the side they use?  
5. **Multi-instance:** Ship single-node only until Redis (or equivalent) is specified.

---

## 8. References

- [bus_finder-architecture-learnings.md](./bus_finder-architecture-learnings.md) — map stack, WS envelope, rate limits.  
- [MatchingService.java](../server/src/main/java/odm/clarity/woleh/places/MatchingService.java) — definition of “matched” for v1.  
- [ws_message.dart](../mobile/lib/core/ws_message.dart) — client-side WS typing.  
- [PRD.md](./PRD.md) §7.5 — FR-L1–L3.
