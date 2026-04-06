# Woleh — Product Requirements Document (PRD)

| Field | Value |
|-------|--------|
| **Product** | Woleh |
| **Document type** | PRD (living document) |
| **Status** | Draft — requirements evolve with discovery |
| **Last updated** | 2026-04-06 |
| **Related** | [Architecture](./ARCHITECTURE.md), [bus_finder learnings](./bus_finder-architecture-learnings.md) |

---

## 1. Executive summary

**Woleh** is a mobile-first product that helps people connect **intent** (what they need, where they are) with **what is moving or available around them** in **near real time**. Users sign in, optionally subscribe to plans that unlock different capabilities, share location and preferences when relevant, and receive **live updates** via the app rather than polling.

The **technical direction** is fixed in [ARCHITECTURE.md](./ARCHITECTURE.md): Flutter client, Spring Boot API, PostgreSQL, WebSocket-based realtime where needed, JWT authentication, and **plan-based access control** on the server.

This PRD states **what** we build and **why**; architecture states **how** we implement it.

---

## 2. Problem statement

- People making mobility or local decisions often lack **timely, trustworthy** information about what is nearby or en route.
- Solutions that rely only on static schedules or manual refresh feel **stale**; users expect **live** status and relevance.
- Building such a product requires **identity**, **optional monetization**, **location and intent** handling, and **efficient delivery** of updates—without exposing users to abuse or unclear data use.

---

## 3. Product vision

**Woleh** becomes the app users open when they want to **see what matters now**—grounded in their context, with clear consent and controls, and powered by a backend designed for **realtime** and **scale**.

---

## 4. Goals and non-goals

### 4.1 Goals

| ID | Goal |
|----|------|
| G1 | **Onboard** users quickly with low friction (phone-based auth acceptable for MVP). |
| G2 | **Authenticate** sessions securely (JWT); **authorize** features by **subscription plan**, not only a static role. |
| G3 | Deliver **realtime updates** to the client for core flows (WebSockets with a stable message contract). |
| G4 | Provide a **profile** users can manage (name, optional contact fields as product allows). |
| G5 | Support **monetization** via subscription plans and payment integration (exact provider TBD). |
| G6 | Meet **privacy and safety** expectations: consent for location, clear stop conditions, rate limits where abuse is likely. |

### 4.2 Non-goals (initial phases)

- Replacing native maps SDKs with a full in-house map stack.
- Building a general-purpose social network or open messaging platform unrelated to the core mobility/discovery value.
- Committing to a specific payment or push provider in this PRD (integrate behind interfaces per architecture).

---

## 5. Target users and personas

Personas are **placeholders** until user research narrows them; they drive requirement priorities.

| Persona | Needs | Success looks like |
|---------|--------|-------------------|
| **Commuter / rider** | Know what is available or approaching; reduce uncertainty and wait. | Timely, accurate live information; trustworthy permissions. |
| **Provider / mover** *(if product includes supply side)* | Reach people who need the service; manage availability. | Clear signals of demand; tools that respect road safety and privacy. |
| **Casual explorer** | Discover options near current context. | Fast load, simple paths, no forced subscription for basic discovery if product allows. |

*Adjust or split personas when the vertical (transit vs. rides vs. local services) is decided.*

---

## 6. User journeys (MVP → v1)

### 6.1 Authentication

1. User opens Woleh.
2. User enters phone number; receives OTP; verifies.
3. New users complete minimal signup (e.g. name); returning users land in the main experience.
4. Session persists securely; logout clears client-held tokens.

### 6.2 Subscription and plans

1. User views available plans and pricing.
2. User selects a plan and completes payment (when payment is integrated).
3. Server enforces plan for **gated** endpoints and realtime features.
4. User sees current subscription status and renewal expectations.

### 6.3 Core value journey *(domain-specific details TBD)*

1. User sets **intent** (e.g. search criteria, route, or preferences—exact UX TBD).
2. User grants **location** when the feature requires it; can revoke or stop activity that shares location.
3. User receives **updates in realtime** (e.g. matches, ETAs, availability) over WebSockets per [ARCHITECTURE.md](./ARCHITECTURE.md).
4. User can **stop** or **clear** the activity (e.g. end search, stop sharing) and expects sharing to stop promptly on the server.

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

### 7.2 Subscription and billing

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-S1 | List subscription plans from server (public or authenticated per product rules). | P0 |
| FR-S2 | Subscribe flow with payment provider integration; webhook or server-side confirmation of status. | P1 |
| FR-S3 | Server-side enforcement: requests for gated capabilities require an active plan (or grace period if product defines one). | P0 |
| FR-S4 | Display subscription status and handling of expired or failed payment (messaging TBD). | P1 |

### 7.3 Realtime and domain features

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-R1 | WebSocket connections authenticated; messages use shared `{ type, data }` envelope. | P0 |
| FR-R2 | Heartbeats or equivalent keepalive; client reconnect strategy (backoff) documented. | P1 |
| FR-R3 | Domain-specific streams (e.g. matches, updates) implemented per vertical; **exact event types** listed in API/docs when built. | P0* |

\*P0 once the core vertical is chosen; placeholder streams acceptable only for scaffolding.

### 7.4 Location and privacy

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-L1 | Request location permission with clear purpose strings; no background tracking beyond product-defined use cases. | P0 |
| FR-L2 | User can stop sharing / deactivate flows that use location; server stops broadcasting associated data. | P0 |
| FR-L3 | Rate limiting on high-frequency location or intent endpoints (server-side). | P1 |

### 7.5 Notifications *(optional phase)*

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-N1 | Push notifications for high-value events (e.g. approaching match, subscription expiry) with user opt-in. | P2 |

### 7.6 Admin / operations *(optional)*

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
| Core action | Domain-specific (e.g. first successful realtime session) | Define when vertical is fixed |
| Retention | D1 / D7 return | Standard product analytics |
| Subscription | Conversion to paid; churn | When billing is live |
| Technical | API error rate, WS disconnect rate, p95 latency | Ops dashboard |

---

## 10. Phased rollout (suggested)

| Phase | Focus | Exit criteria |
|-------|--------|----------------|
| **0 — Foundation** | Repo layout, CI, auth, profile, health | User can sign in and see protected content |
| **1 — Plans** | Plans API, gating, payment integration | Paid plan unlocks gated features end-to-end |
| **2 — Core vertical** | Domain models, REST + WS streams, mobile UX | Core journey works in staging with test data |
| **3 — Hardening** | Rate limits, observability, push (if needed) | SLOs met; runbooks for incidents |

Phases are adjustable; **G1–G3** should not slip far past Phase 0–1.

---

## 11. Dependencies and assumptions

- **Assumption**: Primary client is **Flutter**; backend is **Spring Boot** per architecture.
- **Assumption**: **PostgreSQL** is the system of record; PostGIS only if spatial features are required.
- **Dependency**: SMS/OTP provider for production (dev may use mock OTP).
- **Dependency**: Payment provider when subscriptions go live.
- **Dependency**: App store accounts for distribution.

---

## 12. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Realtime complexity (reconnects, ordering) | Standard envelope, heartbeats, backoff; integration tests |
| Subscription logic drift between client and server | Server is source of truth; client only reflects API |
| Location privacy concerns | Clear UX, minimal retention, documented policy |
| Scope creep on “discovery” | Phase gates; vertical decision recorded in this doc or an ADR |

---

## 13. Open questions

1. **Vertical**: Transit matching, rides, hyperlocal services, or hybrid? (Drives FR-R3 and UX.)
2. **Markets**: Countries, languages, and regulatory constraints (payments, telecom, data residency).
3. **Free tier**: What is available without a paid plan?
4. **Grace period** after subscription lapse: duration and behavior.
5. **Offline**: Read-only cache vs. hard requirement for offline-first.

---

## 14. Document history

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2026-04-06 | Initial PRD for Woleh |

When requirements change materially, bump version and summarize in this table.
