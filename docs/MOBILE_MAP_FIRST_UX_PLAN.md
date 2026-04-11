# Plan: Mobile map-first UX (splash, profile hub, places search, watch XOR broadcast)

This document describes a **navigation and UX restructuring** for the Flutter app under [`mobile/`](../mobile/). It complements live-location behavior in [MAP_LIVE_LOCATION_PLAN.md](./MAP_LIVE_LOCATION_PLAN.md) and place-list APIs in [API_CONTRACT.md](./API_CONTRACT.md).

**Summary:** Map-first `/home`, splash while auth resolves, dedicated `/profile` (logout, subscriptions, edit name), `/places/search` with autosave then return to the map (matches as live peer markers), **mutually exclusive watch vs broadcast** (only one active list), and a fix for profile edit not closing after save.

---

## Implementation checklist

- [x] **Splash / router** — `/splash`, `initialLocation`, redirects for auth loading → splash, splash → auth or `/home`; update [`mobile/test/app/router_redirect_test.dart`](../mobile/test/app/router_redirect_test.dart). *(Done: [`mobile/lib/app/splash_screen.dart`](../mobile/lib/app/splash_screen.dart), [`mobile/lib/app/router.dart`](../mobile/lib/app/router.dart).)*
- [x] **Map home** — Full-page map, search chrome, profile icon, persistent recenter; `WsStatusBanner` + match SnackBars; `/profile` → [`ProfileScreen`](../mobile/lib/features/me/presentation/profile_screen.dart); `/places/search` → [`PlacesSearchScreen`](../mobile/lib/features/places/presentation/places_search_screen.dart); `/map` → `/home`. *(Done: [`map_home_screen.dart`](../mobile/lib/features/home/presentation/map_home_screen.dart), [`live_map_stack.dart`](../mobile/lib/features/location/presentation/live_map_stack.dart), [`location_map.dart`](../mobile/lib/shared/location_map.dart), [`pump_map_home.dart`](../mobile/test/support/pump_map_home.dart).)*
- [x] **Profile screen** — `/profile` → [`ProfileScreen`](../mobile/lib/features/me/presentation/profile_screen.dart); AppBar: plans, edit, sign out; body: avatar, subscription, permissions, limits, place-list + map actions; no duplicate `WsStatusBanner` / match list (map-first). *(Removed `features/home/presentation/home_screen.dart`.)*
- [x] **Places search** — `/places/search`, draft list, autosave with watch-XOR-broadcast clears, permissions, invalidate notifiers, pop back to map. *(Done: [`places_search_screen.dart`](../mobile/lib/features/places/presentation/places_search_screen.dart); save paths await [`meNotifierProvider.future`](../mobile/lib/features/me/presentation/me_notifier.dart) so a cold open of search still resolves `me` before PUT; tests: [`places_search_screen_test.dart`](../mobile/test/features/places/places_search_screen_test.dart).)*
- [ ] **Mode exclusivity** — Same XOR rule on optional `/watch` and `/broadcast` editors (or shared save helper); legacy dual-list migration if needed.
- [ ] **Profile edit pop** — Post-frame `pop` + fallback `go`, widget test.

---

## Current baseline

- **Routing:** [`mobile/lib/app/router.dart`](../mobile/lib/app/router.dart) uses `initialLocation: '/splash'` and redirects (authenticated → `/home` map-first; `/profile` → [`ProfileScreen`](../mobile/lib/features/me/presentation/profile_screen.dart)).
- **Map:** [`LiveMapScreen`](../mobile/lib/features/location/presentation/live_map_screen.dart) wraps [`LocationMap`](../mobile/lib/shared/location_map.dart) (recenter FAB exists **only while not** “following” the user — see `if (widget.self != null && !_followUser)` in `location_map.dart`).
- **Lists:** Watch/broadcast UIs use [`WatchNotifier`](../mobile/lib/features/places/presentation/watch_notifier.dart) / [`BroadcastNotifier`](../mobile/lib/features/places/presentation/broadcast_notifier.dart); server replace is already available as [`PlaceListRepository.putWatchList`](../mobile/lib/features/places/data/place_list_repository.dart) / `putBroadcastList`.
- **Profile edit:** [`ProfileEditScreen`](../mobile/lib/features/me/presentation/profile_edit_screen.dart) calls `context.pop()` after a successful `save()`; opened from profile AppBar (`/me/edit`).

---

## 1) Splash / auth vs home

**Goal:** Brief first route that waits for auth resolution, then sends the user to auth or the main app (map home).

**Approach:**

- Add a **`/splash`** route with a small `SplashScreen` (logo + optional short minimum display via `Future.wait` if you want branding, not strictly required).
- Set `GoRouter.initialLocation` to **`/splash`**.
- Extend **`redirect`** in [`router.dart`](../mobile/lib/app/router.dart):
  - While `authStateProvider` is **loading**: if not already on `/splash`, redirect **to** `/splash` (avoids flashing `/auth/phone` during secure-storage read).
  - When **loaded** and **on `/splash`**: redirect to `/auth/phone` if no token, else **`/home`** (which will become map-first).
- Keep existing rules for `/auth/setup-name`, permission guards, and `/map` if you retain it as an alias.

**Tests:** Update [`router_redirect_test.dart`](../mobile/test/app/router_redirect_test.dart) stubs/expectations for the new initial route and loading behavior.

---

## 2) Home = full-page map + chrome

**Goal:** `/home` is a **full-screen map** centered on the user, with top search, top-right profile, bottom-right recenter.

**Approach:**

- **Refactor** map UI out of `LiveMapScreen` into a reusable widget (e.g. `MapHomeBody`) or fold `LiveMapScreen` into the new home implementation to avoid duplication.
- **Layout:** `Scaffold` with **no** traditional `AppBar` (or a transparent one); use a `Stack`:
  - **Bottom:** full-bleed map (reuse location gate + `LocationMap` from [`live_map_screen.dart`](../mobile/lib/features/location/presentation/live_map_screen.dart)).
  - **Top:** padded “search” `Material` / `SearchBar` **read-only** `onTap` → `context.push('/places/search')` (or similar).
  - **Top-right:** `IconButton` → `context.push('/profile')`.
  - **Bottom-right:** recenter control. Today recenter lives inside `LocationMap` only when `_followUser` is false; **product ask** is a **persistent** corner button — either:
    - **Option A (minimal API change):** add an optional `VoidCallback? onRecenterTap` + `bool showRecenterFab` to `LocationMap` and call the same logic as `_recenterOnUser`, **or**
    - **Option B:** hoist `MapController` to the parent (larger change).
  - Recommend **Option A** for a small, focused diff.
- **Banners / match UI:** [`WsStatusBanner`](../mobile/lib/shared/ws_status_banner.dart) on map home; profile has no duplicate banner. Match cards were removed from profile (map SnackBars + pins). **The map is the primary surface for understanding where matches are:** matched counterparts who publish location appear as **peer markers** from [`peerLocationsNotifierProvider`](../mobile/lib/features/location/presentation/peer_locations_notifier.dart) (fed into [`LocationMap`](../mobile/lib/shared/location_map.dart)). Replace or supplement old “Recent Matches” list tiles with map-centric affordances, e.g. non-blocking **SnackBar** / slim banner when a [`MatchMessage`](../mobile/lib/core/ws_message.dart) arrives, optional **focus or pulse** on the relevant peer marker when its `userId` is known, and clearer **labels/tooltips** than today’s generic `Peer (userId)` where product copy allows. Ephemeral match notifications should not pull the user off the map after search.
- **Live marker motion:** Peer pins **already update** as counterparts move: each `peer_location` WS message updates state in [`PeerLocationsNotifier`](../mobile/lib/features/location/presentation/peer_locations_notifier.dart), and `LiveMapScreen` rebuilds `LocationMap` markers from that map. Implementation work is mainly **UX polish** (smooth updates are automatic on rebuild; avoid unnecessary full-map jank if needed later). Remind users in-copy that **location sharing must be on** for peers to appear ([`LiveMapScreen`](../mobile/lib/features/location/presentation/live_map_screen.dart) already hints when sharing is off).
- **`/map` route:** Either remove and update all `context.push('/map')` to `/home`, or keep `/map` as **redirect → `/home`** for backward compatibility and update call sites gradually.

---

## 3) Profile screen (logout + subscriptions)

**Status:** Implemented as [`ProfileScreen`](../mobile/lib/features/me/presentation/profile_screen.dart) at `/profile` (replaces deleted `home_screen.dart`).

**Contents:** AppBar — **Plans**, **Edit profile**, **Sign out**. Body — avatar, name, phone, tier, `SubscriptionStatusCard`, permissions, limits, gated actions (watch list, broadcast, map home).

---

## 4) Places search screen (list + autosave + mode buttons → back to map)

**Goal:** Tapping the home search field opens a screen where the user builds a **list of place names**, then taps:

- **“Show me buses”** → **autosave** as **watch** list (`putWatchList`), then **return to the map** (`context.pop()` if opened via `push`, or `context.go('/home')` if you ever open search without a stack entry).
- **“Show me passengers”** → **autosave** as **broadcast** list (`putBroadcastList`), then **return to the map** the same way.

**Why map next:** After lists are saved, the server can produce **matches**; the user should land on the **map home** to see **where** matched watchers/broadcasters are. Peer positions are **not** on the watch/broadcast list screens — they are on the map via **`peer_location`** updates.

**Autosave:** Call [`placeListRepositoryProvider`](../mobile/lib/features/places/data/place_list_repository.dart) `.putWatchList(names)` / `.putBroadcastList(names)` with the **draft list** (same trimming/normalization as [`WatchScreen`](../mobile/lib/features/places/presentation/watch_screen.dart) / [`BroadcastScreen`](../mobile/lib/features/places/presentation/broadcast_screen.dart) — e.g. [`place_name_normalizer.dart`](../mobile/lib/core/place_name_normalizer.dart)).

**Permission / errors:**

- Before PUT: read [`meNotifierProvider`](../mobile/lib/features/me/presentation/me_notifier.dart) permissions; if missing `woleh.place.watch` / `woleh.place.broadcast`, **`context.push('/plans')`** (or inline upsell) instead of calling the API.
- Surface `PlaceValidationError` / `PlaceLimitError` / offline errors like existing screens.

**After successful PUT:** `ref.invalidate(watchNotifierProvider)` / `broadcastNotifierProvider` (or `refresh()`) so cached list state stays consistent; **no requirement** to open `/watch` or `/broadcast`. Keep those routes for **secondary** editing (e.g. from profile or future “Manage lists”) if still useful.

**Mutually exclusive mode (watch XOR broadcast):** The user must **not** hold active place names in **both** lists at once — they are either **watching** (looking for buses) or **broadcasting** (showing a route), not both.

- **Places search:** On **“Show me buses”**, after a successful `putWatchList(draft)`, call **`putBroadcastList([])`** when `me.permissions.contains('woleh.place.broadcast')` so any prior broadcast path is cleared. On **“Show me passengers”**, after `putBroadcastList(draft)`, call **`putWatchList([])`** when `woleh.place.watch` is present. If the user lacks permission for the opposing endpoint, skip that clear (they cannot have that list server-side except legacy data — see migration).
- **Server support:** Empty list on PUT **clears** the list ([`PlaceListService`](../server/src/main/java/odm/clarity/woleh/places/PlaceListService.java) / integration tests `*put_emptyList_clearsExisting`). No API change required for v1.
- **Order of operations:** Prefer **save the new mode first**, then **clear the other** (minimizes time with zero active lists if the second call fails; if the clear fails, surface error and offer retry so the user is not stuck in a dual-list state).
- **Secondary screens** (`/watch`, `/broadcast`): Apply the **same rule** when saving from those editors (on save: persist current list, then clear the other). Alternatively, **hide** or **disable** the inactive list UI entirely and route edits only through search — product choice; minimum bar is **no successful save leaves both lists non-empty**.
- **Derived “current mode” for UI** (badge on map/profile): e.g. broadcast non-empty → broadcaster; else watch non-empty → watcher; else none. If **both** non-empty (legacy), run a one-time client migration: clear one side using product rule (e.g. prefer the list the user last edited, or newest by timestamp if available; else clear broadcast) or prompt once.

**Route:** e.g. `GoRoute(path: '/places/search', builder: …)`.

**Tests:** Widget tests for validation (empty list disabled), permission gating, successful PUT, **assert navigation returns to map**, and **assert clearing PUT** is invoked when the user has the opposing permission. Add tests (or extend existing watch/broadcast tests) so saving one list clears the other.

---

## 5) BUG: profile edit does not close after save

**Observed code:** success path calls `context.pop()` in [`profile_edit_screen.dart`](../mobile/lib/features/me/presentation/profile_edit_screen.dart) after `save()` returns true.

**Likely fix (robust across GoRouter timing):**

- After success, schedule navigation on the next frame: `WidgetsBinding.instance.addPostFrameCallback((_) { if (!context.mounted) return; if (context.canPop()) context.pop(); else context.go('/profile'); });` (adjust fallback to whatever shell route is correct once `/profile` exists).
- Optionally **`await context.maybePop()`** if your `go_router` API supports it.

**Regression test:** New widget test with a tiny `GoRouter` shell: `push('/me/edit')`, stub `MeRepository.patchDisplayName` + `MeNotifier` so `save` succeeds, assert stack pops back.

---

## Architecture sketch

```mermaid
flowchart TD
  splash[Splash /splash]
  auth[Auth routes /auth/*]
  home[Map home /home]
  search[Places search /places/search]
  profile[Profile /profile]
  watch[Watch /watch optional]
  broadcast[Broadcast /broadcast optional]
  plans[Plans /plans]

  splash -->|no token| auth
  splash -->|token| home
  home -->|search tap| search
  home -->|profile icon| profile
  search -->|PUT watch then clear broadcast then pop| home
  search -->|PUT broadcast then clear watch then pop| home
  home -->|peer_location WS| peerPins[Peer markers update on map]
  profile --> plans
  profile -->|edit| meEdit[/me/edit]
  profile -.->|optional manage lists| watch
  profile -.->|optional manage lists| broadcast
```

---

## Files likely touched

| Area | Files |
|------|--------|
| Router / splash | [`mobile/lib/app/router.dart`](../mobile/lib/app/router.dart), new `splash_screen.dart`, [`router_redirect_test.dart`](../mobile/test/app/router_redirect_test.dart) |
| Map home | [`live_map_screen.dart`](../mobile/lib/features/location/presentation/live_map_screen.dart) and/or new `map_home_screen.dart`, [`location_map.dart`](../mobile/lib/shared/location_map.dart) |
| Profile | [`profile_screen.dart`](../mobile/lib/features/me/presentation/profile_screen.dart) (replaces removed `home_screen.dart`) |
| Search + mode | New `places_search_screen.dart` (+ optional notifier); updates to [`watch_screen.dart`](../mobile/lib/features/places/presentation/watch_screen.dart) / `broadcast_screen.dart` or shared save helper for XOR clears |
| Bugfix | [`profile_edit_screen.dart`](../mobile/lib/features/me/presentation/profile_edit_screen.dart), new test |
| Call sites | Grep/update `context.push('/map')`, `/home`, match cards, subscription card links if they assumed old home |

---

## Risk notes

- **Autosave** replaces the entire server list for that mode — matches `put*` semantics; **draft** must stay non-empty for the chosen button, but **clearing** the opposite list uses **`names: []`**, which the server treats as a full clear (integration tests: `watchList_put_emptyList_clearsExisting`, `broadcastList_put_emptyList_clearsExisting`).
- **Two-step save:** If the “clear other list” call fails after the primary PUT succeeded, UX should offer **retry** for the clear to restore XOR invariant.
- **Broadcast order:** preserve list order from the search UI when calling `putBroadcastList`.
- **Permission guards:** `/watch` and `/broadcast` still redirect to `/plans` when unauthorized — search screen should mirror that to avoid a PUT that will 403.
- **Match markers vs privacy:** Per product rules, **peer coordinates only flow when users are matched and (for the viewer) sharing is on** ([`PeerLocationsNotifier`](../mobile/lib/features/location/presentation/peer_locations_notifier.dart) ignores `peer_location` when local sharing is off). The map can show **that a match occurred** (WS `match`) even before a peer pin exists; set expectations in UI so users know to enable sharing and wait for the other party.
