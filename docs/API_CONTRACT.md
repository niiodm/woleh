# Woleh — API & permission contract (v1)

This document is the **contract** between the Woleh mobile client and the backend: **REST** shape, **permission** requirements per route, and **WebSocket** conventions. Implementation may live in OpenAPI later; this file is the **source of truth** until then.

**Related:** [ARCHITECTURE.md](./ARCHITECTURE.md), [PRD.md](./PRD.md) §13, [PLACE_NAMES.md](./PLACE_NAMES.md), [ADRs](./adr/README.md).

---

## 1. Conventions

| Item | Value |
|------|--------|
| **Base path** | `/api/v1` |
| **Content-Type** | `application/json; charset=utf-8` |
| **Auth** | `Authorization: Bearer <access_token>` for protected routes |
| **Idempotency** | Optional `Idempotency-Key: <uuid>` on mutating requests where duplicate submits are harmful |
| **Correlation** | Server may echo `X-Request-Id` or generate one; clients may send `X-Request-Id` (optional) |

**Versioning:** Bump `/api/v2` only for breaking changes; additive fields are non-breaking.

---

## 2. Response envelope (REST)

### 2.1 Success

```json
{
  "result": "SUCCESS",
  "message": "Human-readable summary",
  "data": { }
}
```

`data` may be `null` when there is no payload.

### 2.2 Error

```json
{
  "result": "ERROR",
  "message": "Human-readable error",
  "data": null
}
```

Optional `code` (string) may be added for machine handling: `"code": "PERMISSION_DENIED"`.

HTTP status must still reflect the failure (see §7).

---

## 3. Permission catalog (v1)

Strings are **stable identifiers**; copy for users comes from the app (transit wording), not necessarily from these keys.

| Permission | Description |
|--------------|-------------|
| `woleh.account.profile` | Authenticated session; read/update own profile |
| `woleh.plans.read` | Read subscription plan catalog |
| `woleh.place.watch` | Read/write **watch** place-name list |
| `woleh.place.broadcast` | Read/write **broadcast** (drive-through) place-name list |

**Effective permissions** are computed server-side from subscription state and grace rules ([PRD.md](./PRD.md) §13.1, §13.5, §13.6).

### 3.1 Tier limits (v1)

Enforced on the server when validating place lists:

| Tier | `placeWatchMax` | `placeBroadcastMax` | `savedPlaceListMax` | Notes |
|------|-------------------|------------------------|----------------------|--------|
| **free** | 5 | 0 | 10 | No `woleh.place.broadcast` permission |
| **paid** (active or in grace with paid entitlements) | 50 | 50 | From plan row | Both place permissions per PRD; saved-list cap stored on `plans.saved_place_list_max` |

Expose limits in **`GET /me`** (or equivalent) so the client can show UI without hard-coding numbers.

---

## 4. Entitlements object (shared shape)

Returned inside `data` for **`GET /api/v1/me`** and optionally mirrored on subscription status.

```json
{
  "userId": "string-or-long",
  "permissions": [
    "woleh.account.profile",
    "woleh.plans.read",
    "woleh.place.watch"
  ],
  "tier": "free",
  "limits": {
    "placeWatchMax": 5,
    "placeBroadcastMax": 0,
    "savedPlaceListMax": 10
  },
  "subscription": {
    "status": "none",
    "currentPeriodEnd": null,
    "inGracePeriod": false
  }
}
```

| Field | Notes |
|-------|--------|
| `tier` | `free` \| `paid` — coarse UI; **authorization uses `permissions`**, not `tier` alone |
| `limits.placeBroadcastMax` | `0` means user must not send broadcast lists (permission absent) |
| `limits.savedPlaceListMax` | Max persisted **saved place list** templates per user (see saved-lists API when implemented) |
| `subscription` | Extend when payment integration exists; v1 may use `none` / stub |

---

## 5. Endpoint ↔ permission matrix

| Method | Path | Auth | Required permissions | Notes |
|--------|------|------|----------------------|--------|
| POST | `/api/v1/auth/send-otp` | No | — | Rate-limited |
| POST | `/api/v1/auth/verify-otp` | No | — | Returns tokens |
| GET | `/api/v1/subscription/plans` | No | — | Public catalog |
| GET | `/api/v1/me` | Yes | Valid session | Always includes entitlements |
| PATCH | `/api/v1/me/profile` | Yes | `woleh.account.profile` | Partial update |
| POST | `/api/v1/me/location` | Yes | `woleh.place.watch` **or** `woleh.place.broadcast` | Match-scoped Phase 4; sharing must be on; rate-limited |
| PUT | `/api/v1/me/location-sharing` | Yes | `woleh.place.watch` **or** `woleh.place.broadcast` | Opt in/out of publishing fixes |
| GET | `/api/v1/me/places/watch` | Yes | `woleh.place.watch` | |
| PUT | `/api/v1/me/places/watch` | Yes | `woleh.place.watch` | Replace list; enforce `limits.placeWatchMax` |
| GET | `/api/v1/me/places/broadcast` | Yes | `woleh.place.broadcast` | 403 if missing permission |
| PUT | `/api/v1/me/places/broadcast` | Yes | `woleh.place.broadcast` | Replace ordered list; enforce max |
| GET | `/api/v1/subscription/status` | Yes | `woleh.account.profile` | Detailed billing mirror (optional v1) |
| POST | `/api/v1/subscription/checkout` | Yes | `woleh.plans.read` | Returns provider **checkout URL** for WebView; see §6.10, [ADR 0005](../adr/0005-payment-checkout-webview.md) |

**Rule:** If the user lacks a permission, return **403** with `result: "ERROR"` and a clear `message`; do not rely on the client to hide the route only.

---

## 6. REST resources (v1)

### 6.1 `POST /api/v1/auth/send-otp`

**Body:**

```json
{
  "phoneE164": "+233241234567"
}
```

The client does **not** send signup vs login intent. The server looks up whether `phoneE164` is already registered and sends the OTP in all cases (subject to rate limits and abuse controls).

**Success `data`:**

```json
{
  "expiresInSeconds": 300
}
```

---

### 6.2 `POST /api/v1/auth/verify-otp`

**Body:**

```json
{
  "phoneE164": "+233241234567",
  "otp": "123456",
  "productAnalyticsConsent": true
}
```

`productAnalyticsConsent` is optional. When present, it is stored on the user **before** access and refresh tokens are issued so the first `GET /me` matches the client.

**Success `data`:**

```json
{
  "accessToken": "jwt",
  "tokenType": "Bearer",
  "expiresInSeconds": 86400,
  "userId": "1",
  "flow": "login"
}
```

| `flow` value | Meaning |
|--------------|--------|
| `login` | Phone was **already registered**; this OTP verification established a session for an **existing** user. |
| `signup` | Phone was **not** registered; this verification **created** the account (first-time user for this number). |

The client uses `flow` to drive UX (e.g. onboarding vs home). The server is the authority: it derives this from whether the user record existed **before** this verification succeeded.

Signup completion (name, etc.) may be a separate **`PATCH /me/profile`** after first token issuance when `flow` is `signup`, or included in a follow-up endpoint—implementation choice; contract assumes **Bearer** access token for `/api/v1/me*`.

---

### 6.3 `GET /api/v1/me`

**Permissions:** authenticated session.

**Success `data`:** User profile fields **plus** the **entitlements** object (§4), e.g.:

```json
{
  "profile": {
    "userId": "1",
    "phoneE164": "+233241234567",
    "displayName": "Ama",
    "locationSharingEnabled": false,
    "productAnalyticsConsent": false
  },
  "permissions": ["woleh.account.profile", "woleh.plans.read", "woleh.place.watch"],
  "tier": "free",
  "limits": {
    "placeWatchMax": 5,
    "placeBroadcastMax": 0,
    "savedPlaceListMax": 10
  },
  "subscription": {
    "status": "none",
    "currentPeriodEnd": null,
    "inGracePeriod": false
  }
}
```

Clients **must** use `permissions` and `limits` for gating and validation; `tier` is advisory.

**`GET /api/v1/subscription/status`** mirrors the same `permissions`, `tier`, `limits` (including `savedPlaceListMax`), and `subscription` fields as above.

---

### 6.4 `PATCH /api/v1/me/profile`

**Permissions:** `woleh.account.profile`

**Body (partial):**

```json
{
  "displayName": "Ama K.",
  "productAnalyticsConsent": true
}
```

Each field is optional; send only fields to change. Immutable fields (e.g. phone) are not patchable unless product allows.

---

### 6.4.1 `POST /api/v1/me/location`

**Permissions:** at least one of `woleh.place.watch`, `woleh.place.broadcast`.

**Preconditions:** `profile.locationSharingEnabled` must be `true` (set via §6.4.2). Otherwise **403** with `code`: `LOCATION_SHARING_OFF`.

**Body:**

```json
{
  "latitude": 5.6037,
  "longitude": -0.187,
  "accuracyMeters": 12.5,
  "heading": 90.0,
  "speed": 8.2,
  "recordedAt": "2026-04-10T12:00:00Z"
}
```

| Field | Required | Notes |
|-------|----------|--------|
| `latitude` | yes | \[-90, 90\] |
| `longitude` | yes | \[-180, 180\] |
| `accuracyMeters` | no | \> 0 if present |
| `heading` | no | \[0, 360\] if present |
| `speed` | no | ≥ 0 if present |
| `recordedAt` | no | Device time (ISO-8601); server may use receive time for fan-out |

**Success:** `200`, `data` may be `null`. Coordinates are **not** stored on place names. Open WebSocket sessions for **matched** peers receive **`peer_location`** (see §8.2).

**Rate limit:** **429** `RATE_LIMITED` with `Retry-After` when posts arrive faster than configured minimum interval per user (default ~1 Hz; `LOCATION_PUBLISH_MIN_INTERVAL_MS`).

---

### 6.4.2 `PUT /api/v1/me/location-sharing`

**Permissions:** at least one of `woleh.place.watch`, `woleh.place.broadcast`.

**Body:**

```json
{
  "enabled": true
}
```

**Success `data`:**

```json
{
  "enabled": true
}
```

When `enabled` is `false`, `POST /api/v1/me/location` returns **403** `LOCATION_SHARING_OFF` until turned on again. Matched counterparties with an open WebSocket receive **`peer_location_revoked`** (§8.3).

---

### 6.5 `GET /api/v1/subscription/plans`

**Permissions:** none (public).

**Success `data`:** array of plans, each including at least:

```json
{
  "planId": "woleh_paid_monthly",
  "displayName": "Woleh Pro",
  "permissionsGranted": [
    "woleh.account.profile",
    "woleh.plans.read",
    "woleh.place.watch",
    "woleh.place.broadcast"
  ],
  "limits": {
    "placeWatchMax": 50,
    "placeBroadcastMax": 50
  },
  "price": {
    "amountMinor": 999,
    "currency": "GHS"
  }
}
```

Exact pricing fields depend on payment provider integration.

---

### 6.6 `POST /api/v1/subscription/checkout`

**Permissions:** `woleh.plans.read` (user must be authenticated).

**Purpose:** Start a **paid** subscription checkout with the **Ghana-local** payment provider. Per [ADR 0005](../adr/0005-payment-checkout-webview.md), the client opens the returned URL in a **secure WebView**; payment UI is hosted by the provider.

**Body:**

```json
{
  "planId": "woleh_paid_monthly"
}
```

**Success `data`:**

```json
{
  "checkoutUrl": "https://pay.provider.example/checkout/abc123",
  "sessionId": "woleh_psess_01HXYZ",
  "expiresAt": "2026-04-06T12:30:00Z"
}
```

| Field | Notes |
|-------|--------|
| `checkoutUrl` | **HTTPS** only; loaded in WebView |
| `sessionId` | Correlates webhooks and support; opaque to client beyond display/debug |

**Activation:** Paid entitlements apply only after the **server** confirms payment (webhook or verified callback)—client should poll **`GET /me`** or subscribe to push after redirect. See ADR 0005.

**Errors:** `400` unknown plan; `402` / `409` if business rules reject checkout (optional codes).

---

### 6.7 `GET /api/v1/me/places/watch`

**Permissions:** `woleh.place.watch`

**Success `data`:**

```json
{
  "names": ["Accra Central", "Circle"]
}
```

Order may be preserved for display but **matching treats watch as a set** ([PRD.md](./PRD.md) §13.2). Server **dedupes** by normalized form on write.

---

### 6.8 `PUT /api/v1/me/places/watch`

**Permissions:** `woleh.place.watch`

**Body:**

```json
{
  "names": ["Accra Central", "Circle", "Tema"]
}
```

Validation:

- After trim, each name must be non-empty; max length **200** Unicode scalars per name ([PRD.md](./PRD.md) §13.2).
- At most **`limits.placeWatchMax`** entries after dedupe.
- Apply **`normalizePlaceName`** for dedupe and matching per [PLACE_NAMES.md](./PLACE_NAMES.md).

**Errors:** `400` validation; `403` missing permission.

---

### 6.9 `GET /api/v1/me/places/broadcast`

**Permissions:** `woleh.place.broadcast`

**Success `data`:**

```json
{
  "names": ["Stop A", "Stop B", "Stop C"]
}
```

Order is **significant** (drive-through sequence).

---

### 6.10 `PUT /api/v1/me/places/broadcast`

**Permissions:** `woleh.place.broadcast`

**Body:**

```json
{
  "names": ["Stop A", "Stop B", "Stop C"]
}
```

Validation: max **`limits.placeBroadcastMax`** entries after dedupe; same per-name length rules. Dedupe policy: reject duplicates or collapse—**recommend 400** if duplicate normalized names appear if product wants strict lists; otherwise dedupe on save per PRD.

---

## 7. HTTP status mapping

| Status | When |
|--------|------|
| 200 | Success |
| 201 | Created (if used) |
| 400 | Validation / bad input |
| 401 | Missing or invalid token |
| 403 | Authenticated but missing permission or over limit |
| 404 | Resource not found |
| 409 | Conflict (e.g. idempotency replay) |
| 429 | Rate limit |
| 500 | Unexpected server error |

Error body uses envelope §2.2.

---

## 8. WebSockets (v1)

**Base:** Same host as REST; scheme `wss` in production.

| Path | Auth | Permission |
|------|------|------------|
| `/ws/v1/transit` | JWT (see below) | `woleh.place.watch` **or** `woleh.place.broadcast` — server only delivers events the connection is allowed to receive |

**Handshake:** Pass JWT as **`?access_token=<jwt>`** on the `wss` URL ([ADR 0001](../adr/0001-websocket-authentication.md)). Reject with **403** if token invalid or insufficient permissions for requested stream mode.

**Message envelope** ([ARCHITECTURE.md](./ARCHITECTURE.md) §6.2):

```json
{ "type": "heartbeat", "data": "ping" }
{ "type": "match", "data": { } }
{ "type": "peer_location", "data": { } }
{ "type": "peer_location_revoked", "data": { } }
```

### 8.1 `type: match` (illustrative v1)

Sent when a normalized place-name intersection exists between another user’s broadcast path and this user’s watch list (or vice versa), per product rules.

```json
{
  "type": "match",
  "data": {
    "matchedNames": ["Circle"],
    "counterpartyUserId": "42",
    "kind": "broadcast_to_watch"
  }
}
```

Field names are **illustrative**; finalize when implementing realtime matching. **Heartbeat** interval: server-defined (e.g. 15s).

### 8.2 `type: peer_location` (Phase 4)

Sent to each **matched** peer when the other party publishes a fix via **`POST /api/v1/me/location`** (same watch ∩ broadcast rule as matching). Only users with an **open** WebSocket receive the event.

```json
{
  "type": "peer_location",
  "data": {
    "userId": "42",
    "latitude": 5.6037,
    "longitude": -0.187,
    "accuracyMeters": 12.5,
    "heading": 90.0,
    "speed": 8.2,
    "receivedAt": "2026-04-10T12:00:00Z"
  }
}
```

| Field | Notes |
|-------|--------|
| `userId` | Publisher’s user id (string) |
| `latitude` / `longitude` | WGS-84 |
| `accuracyMeters`, `heading`, `speed` | Omitted when not sent on REST publish |
| `receivedAt` | Server time when the event was sent (UTC) |

The publisher does **not** receive their own `peer_location` on the wire.

### 8.3 `type: peer_location_revoked` (Phase 4, §3.4)

Sent to each **matched** peer when the other user turns **off** location sharing (`PUT /me/location-sharing` with `enabled: false`), or when **match adjacency ends** (e.g. a watch or broadcast list change so names no longer intersect). Clients should **remove** that user’s last-known position from the map.

```json
{
  "type": "peer_location_revoked",
  "data": {
    "userId": "42"
  }
}
```

`userId` is the party who stopped sharing.

---

## 9. Client responsibilities

1. Send **`Authorization`** on all protected REST calls.
2. Treat **`permissions` + `limits`** from **`GET /me`** as authoritative for UI; refresh after subscribe/logout.
3. Apply **`normalizePlaceName`** locally only for **preview**; server validates writes.
4. WebSocket: reconnect with backoff on drop; ignore unknown `type` for forward compatibility.

---

## 10. Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-06 | Initial v1 REST + permission matrix + WS outline |
| 1.1 | 2026-04-06 | Auth: removed `purpose` from send/verify OTP; `verify-otp` returns `flow`: `login` \| `signup` |
| 1.2 | 2026-04-06 | WebSocket auth: query `access_token` per ADR 0001; `POST …/subscription/checkout` for WebView payment per ADR 0005 |
| 1.3 | 2026-04-10 | Phase 4: `POST /me/location`, `PUT /me/location-sharing`, profile `locationSharingEnabled`, WebSocket `peer_location` (§8.2), `peer_location_revoked` (§8.3) |
