# Plan: Server-side closest-peer ordering

Order WebSocket delivery so **nearer** matched counterparties are notified first: `match` events after place-list saves, and `peer_location` fan-out after each accepted `POST /api/v1/me/location`.

**Scope:** single-JVM in-memory last-known positions (same operational model as [`MatchAdjacencyRegistry`](../server/src/main/java/odm/clarity/woleh/places/MatchAdjacencyRegistry.java)); see [ADR 0008: Match-scoped live location](./adr/0008-match-scoped-live-location.md).

---

## Step 1 — Haversine helper

**Goal:** Pure distance utility with no new Gradle dependencies.

1. Add a small class under `server/src/main/java/odm/clarity/woleh/location/` (e.g. `GeoDistance`) with a static `haversineMeters(double lat1, double lon1, double lat2, double lon2)` using the standard great-circle formula.
2. Add `GeoDistanceTest` with at least one pair of known coordinates and an expected distance within a small tolerance (e.g. a few meters).

**Done when:** `./gradlew test` passes and the test documents the reference points used.

---

## Step 2 — Last-known location store

**Goal:** Thread-safe cache of each user’s most recent published fix (ephemeral; cleared on restart).

1. Add `@Component` `LastKnownLocationStore` in the same package (or adjacent under `location/`).
2. API (suggested):
   - `void put(long userId, double latitude, double longitude)` — overwrite prior value.
   - `Optional<LatLng>` or `Optional<double[]>` `get(long userId)` for readers.
3. Back with `ConcurrentHashMap<Long, …>`; use an immutable `record` for the stored point if convenient.
4. Javadoc: best-effort ordering, cold users have no entry, restart clears state, not shared across JVMs.

**Done when:** Class compiles, Spring can construct it, and Javadoc states the caveats above.

---

## Step 3 — Location publish: record position + ordered fan-out

**Goal:** After validation, persist publisher position and send `peer_location` to peers **closest first** (by last-known peer position vs **this request’s** coordinates).

1. Inject `LastKnownLocationStore` into [`LocationPublishService`](../server/src/main/java/odm/clarity/woleh/location/LocationPublishService.java).
2. In `publish`, after all checks pass and before building/sending events:
   - `store.put(userId, request.latitude(), request.longitude())` (or equivalent field accessors).
3. Replace raw `Set` iteration over `getCounterparties` with:
   - Copy peer IDs to a list.
   - Sort by: distance from **current request** lat/lng to `store.get(peer)`; peers **without** a stored position sort **after** those with one; tie-break by `peerId` ascending for stability.
4. Iterate the sorted list and call `sendPeerLocationEvent` as today.

**Done when:** Behavior for 0/1 peer is unchanged; multi-peer order is deterministic and distance-based when positions exist.

---

## Step 4 — Matching: collect pairs, sort, then dispatch

**Goal:** When many lists match, process counterparties in **ascending distance** from the **initiator** (user whose list was just saved).

1. Inject `LastKnownLocationStore` into [`MatchingService`](../server/src/main/java/odm/clarity/woleh/places/MatchingService.java).
2. **`dispatchBroadcastMatches(broadcastUserId, …)`**
   - Initiator = `broadcastUserId`.
   - Scan watch lists as today, but **collect** each non-empty intersection as `(watcherUserId, intersection)` (skip self).
   - Origin = `store.get(broadcastUserId)`. If empty, sort collected rows by `watcherUserId` only (stable, explicit fallback).
   - If origin present, sort by Haversine(origin, `store.get(watcherUserId)`), unknown watcher position last, then `watcherUserId`.
   - For each row in sorted order, call existing `sendMatchToUser` twice (watcher then broadcaster, preserving current semantics per pair).
3. **`dispatchWatchMatches(watchUserId, …)`**
   - Same pattern with initiator = `watchUserId`, counterparties = broadcast list owners.

**Done when:** Logic matches the old notifications for a single counterparty; with multiple counterparties, dispatch order follows the comparator above.

---

## Step 5 — Tests

**Goal:** Lock ordering in without brittle full-integration tests.

1. **`LocationPublishServiceTest`**
   - Pass a real `LastKnownLocationStore` into the service (or test config) instead of mocking it.
   - Pre-seed two peers with different coordinates; publisher at a third point closer to peer A than B.
   - Use `Mockito.inOrder(wsSessionRegistry)` to assert `sendPeerLocationEvent` runs for **A before B** (by peer id captured in `verify`).
2. **`MatchingServiceTest`**
   - Inject store + pre-seed initiator and two counterparties with distinct positions.
   - Assert first `sendMatchEvent` calls follow closest-counterparty-first (again `inOrder` or ordered captors).

**Done when:** `./gradlew :server:test` (or project equivalent) is green.

---

## Step 6 — Contract note (optional)

**Goal:** Document best-effort behavior for API consumers.

1. In [`API_CONTRACT.md`](./API_CONTRACT.md), WebSocket section (~§8), add one sentence: when multiple counterparties receive the same logical event, the server may deliver in **approximate ascending distance** using last-known positions; not guaranteed across restarts or multiple instances.

**Done when:** Wording is merged and matches actual implementation.

---

## Step 7 — Manual smoke check (optional)

1. Two test accounts, matched names, both sharing location.
2. Confirm in logs or client order that nearer peer updates are observable first when both receive events in one burst (if your client exposes order).

---

## Out of scope (follow-ups)

- **`peer_location_revoked`:** Same distance sort is optional; low impact.
- **Multi-instance / Redis:** Requires shared store or recomputation; separate architectural change (ADR 0008 follow-up).

---

## Scalability note (brief)

The incremental cost of the map + sort is small relative to existing **full-list scan** matching on each PUT. Very large scale (many JVMs, huge fan-out) needs horizontal and data-layer changes beyond this plan.

---

## Checklist

| Step | Description |
|------|-------------|
| 1 | `GeoDistance` + unit test |
| 2 | `LastKnownLocationStore` component |
| 3 | `LocationPublishService`: `put` + sorted peer fan-out |
| 4 | `MatchingService`: collect, sort, dispatch |
| 5 | Extended service tests with `inOrder` |
| 6 | Optional `API_CONTRACT.md` sentence |
| 7 | Optional manual smoke |
