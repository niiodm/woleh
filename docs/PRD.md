# Woleh — Product Requirements Document (PRD)

| Field | Value |
|-------|--------|
| **Product** | Woleh |
| **Document type** | PRD (living document) |
| **Status** | Active — Phase 0 complete; Phase 1 planning |
| **Last updated** | 2026-04-07 (v0.12 Phase 1 planning) |
| **Related** | [Architecture](./ARCHITECTURE.md), [API contract](./API_CONTRACT.md), [Phase 0 implementation](./PHASE_0_IMPLEMENTATION.md), [Phase 1 implementation](./PHASE_1_IMPLEMENTATION.md), [ADRs](./adr/README.md), [bus_finder learnings](./bus_finder-architecture-learnings.md) |

---

## 1. Executive summary

**Woleh** is a **transit** mobile app: it helps **riders** and **people operating vehicles** coordinate using **place names** (stops, landmarks, terminals—whatever people type) and **near real time** updates. Users sign in, optionally subscribe to plans that grant a **list of permissions** (capabilities), and express intent using **lists of place names** (not stored routes with map geometry): one flow lists places along the path the vehicle will **drive through**, another lists places where a rider wants to **see buses / service**. Matching uses **those names only**—**no latitude/longitude** on names; equivalence is by **string matching** (see [PLACE_NAMES.md](./PLACE_NAMES.md)). Users receive **live updates** via the app where the product provides streams.

**Copy, onboarding, and store listings** should consistently **sound like transit** (buses, stops, riders, drivers-as-operators). The **backend** in this repo is architected as a **general-purpose** foundation (permissions, place lists, realtime) suitable for **hyperlocal discovery** or other apps later; **Woleh** is the transit-branded client on top of that platform. See [ARCHITECTURE.md](./ARCHITECTURE.md) §1.1.

Woleh **does not** split users into fixed product roles such as “passenger” vs “driver” in the codebase or account model. The same user account can hold any combination of capabilities over time; **what they may do** is determined only by **subscription-backed permissions** (enforced on the server; reflected in the mobile UI for visibility).

The **technical direction** is fixed in [ARCHITECTURE.md](./ARCHITECTURE.md): Flutter client, Spring Boot API, PostgreSQL, WebSocket-based realtime where needed, JWT authentication, and **permission-based access control** derived from the active subscription. The **v1 API and permission matrix** are specified in [API_CONTRACT.md](./API_CONTRACT.md).

This PRD states **what** we build and **why**; architecture states **how** we implement it.

---

## 2. Problem statement

- **Transit riders** often lack **timely, trustworthy** information about which service is heading where they need to go, especially where schedules are weak or informal.
- **Operators** waste time or miss demand when they cannot see **who cares about which stops** along their path.
- Solutions that rely only on static schedules or manual refresh feel **stale**; users expect **live** relevance.
- Building Woleh requires **identity**, **optional monetization**, **intent expressed as place names**, and **efficient delivery** of updates—without exposing users to abuse or unclear data use. (Optional GPS or maps features are out of scope for the core **name-only** place model.)

---

## 3. Product vision

**Woleh** becomes the transit app people open when they want to **see what matters on the road now**—which places matter along the route, who is moving, and who is waiting—grounded in **named places** they already use, with clear consent and controls. The same platform architecture can support **other discovery apps** later; **Woleh** stays unmistakably **transit** in voice and experience.

---

## 4. Goals and non-goals

### 4.1 Goals

| ID | Goal |
|----|------|
| G1 | **Onboard** users quickly with low friction (phone-based auth acceptable for MVP). |
| G2 | **Authenticate** sessions securely (JWT); **authorize** by an **explicit permission set** from the active subscription (not fixed passenger/driver types). |
| G3 | Deliver **realtime updates** to the client for core flows (WebSockets with a stable message contract). |
| G4 | Provide a **profile** users can manage (name, optional contact fields as product allows). |
| G5 | Support **monetization** via subscription plans and payment integration (exact provider TBD). |
| G6 | Meet **privacy and safety** expectations: clear stop conditions for any live activity, rate limits where abuse is likely. |
| G7 | Use **simple place-name lists** for intent (drive-through vs watch); **no** persisted route objects with coordinates; match on **names** per [ARCHITECTURE.md](./ARCHITECTURE.md). |
| G8 | **Product and copy** present Woleh as **transit** (riders, vehicles, stops/places along the way); **backend** design remains **reusable** for non-transit discovery clients per [ARCHITECTURE.md](./ARCHITECTURE.md) §1.1. |

### 4.2 Non-goals (initial phases)

- Replacing native maps SDKs with a full in-house map stack.
- Storing or requiring **coordinates per place name** for the core matching flow (names only unless a future ADR adds optional geodata).
- Building a general-purpose social network or open messaging platform unrelated to **transit** value.
- Shipping **non-transit** branded experiences inside the **Woleh** app (other verticals belong in separate apps/clients on the shared backend if desired).
- Committing to a specific payment or push provider in this PRD (integrate behind interfaces per architecture).

---

## 5. Target users and scenarios

Users are **not** bucketed into immutable types (e.g. passenger vs driver). The same person may use different capabilities on different days; **permissions** decide what is available.

These **scenarios** describe **transit** jobs-to-be-done and inform UX copy and permission catalog—they are not separate account categories.

| Scenario | Needs | Success looks like |
|----------|--------|-------------------|
| **Rider** | Name **stops or places** they care about along routes; see **buses / service** that matter. | Timely live information; **watch** permission; matches by **place name** overlap. |
| **Vehicle operator** | Declare **place names** along the path they will **drive through**; be visible to matching riders. | **Broadcast** permission; **list of drive-through place names**—no route geometry stored. |
| **Rider exploring** | Try the app with a limited or free permission set. | Fast load; clear **transit** value; upgrade path for more capabilities. |

*Extend the **permission catalog** as features grow; keep wording **transit-native** in the Woleh client.*

---

## 6. User journeys (MVP → v1)

### 6.1 Authentication

1. User opens Woleh.
2. User enters phone number; receives OTP; verifies. The client does **not** choose “signup” vs “login”; the **backend** decides whether the number is already registered and returns **`flow`** (`login` or `signup`) on OTP verification per [API_CONTRACT.md](./API_CONTRACT.md) §6.2.
3. **`signup`:** user completes minimal onboarding (e.g. name). **`login`:** user lands in the main experience (or profile completion if product requires).
4. Session persists securely; logout clears client-held tokens.

### 6.2 Subscription, plans, and permissions

1. User views available plans and pricing; each plan exposes the **permissions** it includes (human-readable + stable machine identifiers).
2. User selects a plan and completes payment (when payment is integrated).
3. Server attaches the plan’s permission set to the active subscription and enforces permissions on **every** gated REST and WebSocket capability.
4. Mobile app fetches effective permissions (or receives them with session/profile) and **shows or hides** UI affordances accordingly—without duplicating business rules; server remains authoritative.
5. User sees current subscription status, included permissions, and renewal expectations.

### 6.3 Core value journey — place names and matching

1. User with permission to **broadcast** enters an ordered (or unordered—product rule) **list of place names** representing where they will drive through. The system stores **strings only**—no lat/long per name.
2. User with permission to **watch** enters a **list of place names** where they want to see relevant buses/activity.
3. The server **matches** by **comparing place names** (intersection / containment rules as specified—e.g. “any overlapping name”), after **normalization** (trim, case, etc.—documented).
4. User receives **updates in realtime** (e.g. relevant activity) over WebSockets per [ARCHITECTURE.md](./ARCHITECTURE.md) when implemented.
5. User can **clear** or **stop** their broadcast or watch list; server stops using that data for matching promptly.

---

## 7. Functional requirements

Priorities: **P0** = MVP blocker, **P1** = soon after MVP, **P2** = later.

### 7.1 Identity and account

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-A1 | Phone OTP sign-in and signup flow with validated inputs. | P0 |
| FR-A2 | JWT-based API access; token refresh or re-auth policy documented and implemented. | P0 |
| FR-A3 | User profile: read/update profile fields defined by product (immutable fields such as phone policy TBD). | P0 |
| FR-A4 | Logout and local credential clearing on client. | P0 |

### 7.2 Subscription, permissions, and billing

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-S1 | List subscription plans from server (public or authenticated per product rules); each plan includes a **defined list of permission strings** the plan grants. | P0 |
| FR-S2 | Subscribe flow with payment provider integration; webhook or server-side confirmation of status. | P1 |
| FR-S3 | **Server-side enforcement**: every gated capability checks required permission(s); active subscription must include those permissions (grace period if product defines one). | P0 |
| FR-S4 | Display subscription status and handling of expired or failed payment (messaging TBD). | P1 |
| FR-S5 | **Effective permissions** available to the client after login (e.g. via profile, subscription status, or dedicated endpoint) for **UI gating**; permission strings are stable and documented. | P0 |
| FR-S6 | Mobile app uses permission checks at navigation and component boundaries to show/hide features; **no** parallel passenger/driver module split—use feature areas + permission guards. | P0 |

### 7.3 Realtime and domain features

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-R1 | WebSocket connections authenticated; messages use shared `{ type, data }` envelope. | P0 |
| FR-R2 | Heartbeats or equivalent keepalive; client reconnect strategy (backoff) documented. | P1 |
| FR-R3 | **Transit** domain streams (e.g. matches, live updates) for Woleh; **exact event types** listed in API/docs when built. | P0* |

\*P0 for core journey; placeholder streams acceptable only for scaffolding.

### 7.4 Place names (core domain)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-P1 | Users with the appropriate permission can set **drive-through place names** (list of strings); system does **not** store coordinates on these names. | P0 |
| FR-P2 | Users with the appropriate permission can set **watch place names** (list of strings); same rule—**no** lat/long on names. | P0 |
| FR-P3 | Matching determines relevance using **string comparison** after shared normalization per [PLACE_NAMES.md](./PLACE_NAMES.md); client and server use the same algorithm and test vectors. | P0 |
| FR-P4 | No **route** aggregate with geometry: no bus_finder-style complex route objects; persistence is lists + metadata (IDs, active flags) as needed. | P0 |

### 7.5 Location and privacy *(optional / future)*

Core MVP matching does **not** depend on GPS. If the product later adds maps or device location, treat it as additive and document in an ADR.

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-L1 | If device location is used: request permission with clear purpose strings; no background tracking beyond product-defined use cases. | P2 |
| FR-L2 | User can stop any flow that uses device location; server stops associated processing. | P2 |
| FR-L3 | Rate limiting on high-frequency endpoints (server-side). | P1 |

### 7.6 Notifications *(optional phase)*

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-N1 | Push notifications for high-value events (e.g. approaching match, subscription expiry) with user opt-in. | P2 |

### 7.7 Admin / operations *(optional)*

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-O1 | Health checks and basic observability for production operations. | P1 |
| FR-O2 | Admin or support tools TBD (out of scope until defined). | P2 |

---

## 8. Non-functional requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR-1 | Performance | Core REST paths respond within agreed SLO (e.g. p95 below 500 ms under nominal load) once baselined. |
| NFR-2 | Reliability | Graceful degradation when realtime is unavailable; user sees clear errors and retry paths. |
| NFR-3 | Security | HTTPS/TLS; secure token storage on mobile; server validates all privileged operations; rate limits on sensitive endpoints. |
| NFR-4 | Privacy | Data minimization; retention policy documented; comply with applicable regulations as product jurisdiction is set. |
| NFR-5 | Maintainability | API contracts exercised via `.http` collections or automated tests; [ARCHITECTURE.md](./ARCHITECTURE.md) kept current. |
| NFR-6 | Accessibility | Mobile UI targets WCAG-minded practices for text, contrast, and touch targets (exact level TBD). |

---

## 9. Success metrics

Metrics should be **instrumented** after baseline; initial candidates:

| Metric | Definition | Notes |
|--------|------------|--------|
| Activation | % of new users who complete signup and reach main experience | Funnel in analytics |
| Core action | e.g. first successful **transit** name-based match or realtime session | Define precise analytics event in implementation |
| Retention | D1 / D7 return | Standard product analytics |
| Subscription | Conversion to paid; churn | When billing is live |
| Technical | API error rate, WS disconnect rate, p95 latency | Ops dashboard |

---

## 10. Phased rollout (suggested)

| Phase | Focus | Exit criteria | Status |
|-------|--------|----------------|--------|
| **0 — Foundation** | Repo layout, CI, auth, profile, health | User can sign in and see protected content ([codable steps](./PHASE_0_IMPLEMENTATION.md)) | ✅ Complete (2026-04-07) |
| **1 — Plans** | Plans API, gating, payment integration | Paid plan unlocks gated features end-to-end ([codable steps](./PHASE_1_IMPLEMENTATION.md)) | Planned |
| **2 — Core transit journey** | Domain models, REST + WS streams, **transit** mobile UX | Rider/operator place-name flow works in staging | Planned |
| **3 — Hardening** | Rate limits, observability, push (if needed) | SLOs met; runbooks for incidents | Planned |

Phases are adjustable; **G1–G3** should not slip far past Phase 0–1.

---

## 11. Dependencies and assumptions

- **Assumption**: **Woleh** is the **transit**-positioned Flutter app; the **backend** is intentionally **general-purpose** enough to reuse for hyperlocal or other discovery clients later ([ARCHITECTURE.md](./ARCHITECTURE.md) §1.1).
- **Assumption**: Primary client is **Flutter**; backend is **Spring Boot** per architecture.
- **Assumption**: **PostgreSQL** is the system of record; **PostGIS not required** for core name-only matching.
- **Dependency**: SMS/OTP provider for production (dev may use mock OTP).
- **Dependency**: Payment provider when subscriptions go live.
- **Dependency**: App store accounts for distribution.

---

## 12. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Realtime complexity (reconnects, ordering) | Standard envelope, heartbeats, backoff; integration tests |
| Subscription or permission logic drift between client and server | Server is source of truth for enforcement; client uses API permission list only for UX |
| Typos / inconsistent spellings for the same place | [PLACE_NAMES.md](./PLACE_NAMES.md) baseline; optional alias list or “did you mean?” (ADR) if needed later |
| Location privacy concerns *(if GPS added later)* | Clear UX, minimal retention, documented policy |
| Scope creep beyond **transit** in the Woleh app | Phase gates; non-transit products use separate clients or ADR |

---

## 13. Resolved defaults (v1)

These replace the former open questions. Revisit when launching or when product research contradicts them.

### 13.1 Permission catalog (v1)

- **Naming:** Dot-separated, `woleh.` prefix for Woleh-scoped permissions (leaves room for other products on a shared API later).

| Permission | Meaning |
|------------|--------|
| `woleh.account.profile` | Sign in, read/update own profile |
| `woleh.plans.read` | View subscription plans (pricing UI) |
| `woleh.place.watch` | Set and manage **watch** place-name list |
| `woleh.place.broadcast` | Set and manage **broadcast** (drive-through) place-name list |

- **Plans map to permissions** in data: each plan record includes the **list of permission strings** it grants. Example **v1** product split (adjustable):
  - **Free (no paid subscription):** `woleh.account.profile`, `woleh.plans.read`, `woleh.place.watch` — **watch list capped at 5** place names (server-enforced); **no** `woleh.place.broadcast`.
  - **Paid:** adds `woleh.place.broadcast`; raises watch list limit to **50**; broadcast list limit **50**.

Exact pricing and plan names are product/marketing; **limits** are the defaults above.

### 13.2 Place-name rules (v1)

- **Broadcast (drive-through) list:** **Ordered** — order is meaningful (sequence along the intended path).
- **Watch list:** **Unordered** — treated as a **set** for matching (order ignored).
- **Matching rule:** After [PLACE_NAMES.md](./PLACE_NAMES.md) normalization, a **match** exists if the **intersection** of the watch set and the broadcast list (as sets of normalized strings) is **non-empty**.
- **Limits:** Max **50** entries per list (broadcast or watch); max **200** Unicode scalar values per place name; reject empty strings after trim; duplicates **allowed** in input but **dedupe** by normalized equality when matching/storing (product choice: **dedupe on save** recommended).

### 13.3 Backend reuse (v1)

- **Single deployment, single tenant** for Woleh. A second app or multi-tenant separation requires an **ADR** before implementation; not assumed for MVP.

### 13.4 Markets and jurisdiction (v1)

- **Launch jurisdiction:** **Ghana** only for v1 ([ADR 0004](./adr/0004-jurisdiction-ghana.md)). Expansion requires PRD + ADR updates.
- **App UI:** **English** first.
- **Phone auth:** **E.164**; **+233** expected for primary users.
- **Currency:** **GHS** for pricing and checkout.
- **Payments:** Local provider; checkout completed in a **secure WebView** loading the provider’s hosted UI ([ADR 0005](./adr/0005-payment-checkout-webview.md)). Card/bank details are not collected by Woleh.
- **Legal entity and data residency:** Fix before production launch and record in deployment runbooks; hosting should align with Ghana-facing service ([ADR 0004](./adr/0004-jurisdiction-ghana.md)).

### 13.5 Free tier (v1)

- As in §13.1: free users get **watch-only** (up to **5** names), **no** broadcast. **Paid** unlocks broadcast and higher caps.

### 13.6 Grace period (v1)

- **7 calendar days** after subscription end (or recorded end datetime). During grace, **keep the same permissions** as immediately before lapse. **After** grace ends, enforce **free-tier** permissions (§13.1). No partial refunds specified in this doc.

### 13.7 Offline (v1)

- **Online-first.** The client may **cache** last-known profile and place lists for **read-only display** when offline; **no** requirement for offline-first or offline mutations for MVP.

### 13.8 Future review

- Alias lists for place names, fuzzy matching, multi-language UI, and multi-tenant API remain **out of scope** until explicitly prioritized.

---

## 14. Document history

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2026-04-06 | Initial PRD for Woleh |
| 0.2 | 2026-04-06 | No passenger/driver product split; subscription permissions for server + mobile UI gating (FR-S5, FR-S6) |
| 0.3 | 2026-04-06 | Place-name lists only (no route objects); no coordinates on names; string matching (FR-P1–FR-P4); location FRs deferred to optional |
| 0.4 | 2026-04-06 | Documented normalization pipeline in [PLACE_NAMES.md](./PLACE_NAMES.md); FR-P3 points to spec |
| 0.5 | 2026-04-06 | **Transit** product positioning and copy; backend as reusable platform ([ARCHITECTURE.md](./ARCHITECTURE.md) §1.1); G8; open questions updated |
| 0.6 | 2026-04-06 | Former §13 open questions resolved with **v1 defaults** (permissions, place rules, reuse, markets, free tier, grace, offline) |
| 0.7 | 2026-04-06 | Linked [API_CONTRACT.md](./API_CONTRACT.md) (REST v1, permission matrix, WebSockets) |
| 0.8 | 2026-04-06 | Auth: server-driven login vs signup (`flow` on verify-otp); PRD §6.1 aligned |
| 0.9 | 2026-04-06 | Ghana jurisdiction; WebView + local provider payments; linked [adr](./adr/README.md) |
| 0.10 | 2026-04-07 | Linked [Phase 0 implementation](./PHASE_0_IMPLEMENTATION.md) codable breakdown |
| 0.11 | 2026-04-07 | Phase 0 complete — status updated; phased rollout table gains Status column |
|| 0.12 | 2026-04-07 | Linked [Phase 1 implementation](./PHASE_1_IMPLEMENTATION.md) codable breakdown; Phase 1 row updated |

When requirements change materially, bump version and summarize in this table.
