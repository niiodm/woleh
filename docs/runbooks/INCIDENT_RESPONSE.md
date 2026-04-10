# Incident response runbook

Operational playbooks for **likely production failures** on the Woleh stack (API, WebSocket, Postgres, push). Use together with [`SLO_BASELINE.md`](./SLO_BASELINE.md) for latency and alerting context.

## General principles

1. **Stabilize** — stop bleeding (rollback, scale, feature flag, rate limit).
2. **Communicate** — status page / stakeholders; short written timeline.
3. **Evidence** — correlation IDs (`X-Request-Id`), `userId` in logs, metrics, traces.
4. **Post-incident** — blameless review; file issues for code or runbook gaps.

---

## 1. WebSocket session leak

**Symptoms**

- Gauge **`woleh.ws.sessions.active`** rises without bound while real concurrent users stay flat.
- Memory pressure on API nodes; degraded WS delivery.

**Likely causes**

- Disconnect paths not running: client killed network, proxy idle timeout, missing `afterConnectionClosed` / error handling in **`TransitWebSocketHandler`**.
- Registry (`WsSessionRegistry`) not deregistering stale sessions when send fails.

**Mitigation**

1. Confirm spike in gauge vs. unique users (analytics or auth metrics).
2. Inspect **`TransitWebSocketHandler`** logs for connect without matching disconnect.
3. **Rolling restart** of API instances clears in-memory registry (acceptable short-term mitigation).
4. If leak reproduces quickly, capture thread dumps and WS logs; patch handler/registry to remove closed sessions on send failure (see existing `WsSessionRegistry` patterns).

**Prevention**

- Synthetic WS clients that connect/disconnect on a schedule in staging.
- Alert on sustained growth of `woleh.ws.sessions.active` (see `SLO_BASELINE.md`).

---

## 2. Match dispatch latency spike

**Symptoms**

- **`woleh.match.evaluation`** timer p95 rises; users report slow “Save” on watch/broadcast lists.
- HTTP p95 on `PUT /api/v1/me/places/*` may rise with it.

**Likely causes**

- v1 algorithm scans **all** complementary lists in memory (`MatchingService`); cost grows with the number of active lists (O(n)).
- Sudden spike in list sizes or number of concurrent PUTs.

**Mitigation**

1. Confirm timer and PUT latency in Prometheus / Actuator.
2. **Operational:** encourage smaller lists; temporarily **lower** `woleh.ratelimit.place-list.requests-per-minute` if overload is from abusive clients (trade-off: more429s).
3. **Capacity:** scale API horizontally (each node still does full scan unless architecture changes—prefer reducing load first).
4. **Long-term:** indexed PostgreSQL `jsonb` overlap or normalized join table (requires ADR and migration).

**Prevention**

- Track timer percentiles after major growth in MAU or list counts.
- Load tests that simulate large broadcast/watch populations before campaigns.

---

## 3. Rate limit false positives

**Symptoms**

- Legitimate users receive **429** on `PUT /api/v1/me/places/watch` or `…/broadcast` with **`Retry-After`**.
- Support reports “can’t save list” clustered in time or per user.

**Likely causes**

- **`PlaceListRateLimiter`** fixed window too aggressive for real usage (`woleh.ratelimit.place-list.requests-per-minute`).
- Misconfigured **per-user** key (must not be global across users).

**Mitigation**

1. Confirm code path uses **per-user** limiter key (see `PlaceListController` + limiter).
2. **Raise** `woleh.ratelimit.place-list.requests-per-minute` via config; **restart** nodes (in-memory limiter is per instance—multi-instance behavior needs ADR for Redis, etc.).
3. If429s correlate with a single IP but many users, investigate proxy/NAT; OTP and place limits are different—don’t conflate.

**Prevention**

- Monitor429 rate by route; alert on step changes after deploys.
- Document expected “power user” edits per minute for product.

---

## 4. Database migration failure (Flyway)

**Symptoms**

- Deploy fails on startup; logs show Flyway validation or migration error.
- App does not reach healthy.

**Mitigation**

1. Read Flyway output and **`flyway_schema_history`** in Postgres: which script failed, checksum, whether it partially applied.
2. **Do not** “fix forward” on production without a plan. Typical safe path:
   - Restore DB snapshot taken **before** migration (or failover to standby from pre-migration).
   - Ship fixed migration or corrective script; test on a copy.
3. Re-run migration from clean state per DBA procedure.

**Special case: `normalized_names`**

- If **`PlaceNameNormalizer`** algorithm changes, existing `user_place_lists.normalized_names` may be wrong for matching. **`V5`** migration comments in `server/src/main/resources/db/migration/` describe re-normalization expectations. Coordinate a **data fix** with any schema change.

**Prevention**

- Migrations tested on production-sized copies.
- Expand/contract migrations split into reversible steps where possible.

---

## 5. Subscription / grace period edge case

**Symptoms**

- User insists they are paid but API/UI shows free limits or missing permissions.
- Checkout succeeded but entitlements did not update.

**Mitigation**

1. Inspect **`subscriptions`** row: `status`, **`current_period_end`**, **`grace_period_end`**, `provider_subscription_id`.
2. Compare timestamps to **UTC now**; grace logic lives in **`EntitlementService`**.
3. Enable **DEBUG** temporarily for `odm.clarity.woleh.subscription` (or relevant package) to see resolved tier in logs—avoid leaving DEBUG on in prod indefinitely.
4. If webhook or provider lag: reconcile with payment provider dashboard; manual status fix only with written approval.

**Prevention**

- Alerts on webhook error rates and subscription webhook DLQ (if present).

---

## 6. Push token staleness (FCM)

**Symptoms**

- User stops receiving match or subscription reminders on device; others receive pushes.

**Likely causes**

- FCM tokens **rotate**; old rows in **`device_tokens`** are invalid.
- User denied notification permission after upgrade; client no longer registers.
- **`woleh.push.enabled`** false or **`RealFcmService`** misconfigured (service account, project ID).

**Mitigation**

1. Check **`device_tokens.updated_at`** for the user; stale rows (weeks old) suggest no successful re-registration.
2. Confirm mobile **`PushBootstrap`** (`kPushEnabled`) / client logs: permission, `getToken`, `POST /api/v1/me/device-token`.
3. Server-side: **`StubFcmService`** only logs—no real push. Production needs **`woleh.push.enabled=true`** and valid FCM credentials.
4. Ask user to open app once (re-register); if still broken, delete token row and have user re-enable notifications.

**Prevention**

- Monitor FCM send failures in logs (`RealFcmService`); alert on error rate spikes.
- Document token refresh behavior in release notes when bumping `firebase_messaging`.

---

## Escalation

| Severity | Examples | Response |
|----------|----------|----------|
| SEV1 | API down, data loss risk, auth wide open | Page immediately; incident commander |
| SEV2 | Major feature broken (WS, payments), partial outage | Page on-call; update within 1h |
| SEV3 | Degraded latency, isolated bugs | Business hours; ticket + metric snapshot |

## References

- `docs/PHASE_3_IMPLEMENTATION.md` — Phase 3 Step 4.2
- `docs/runbooks/SLO_BASELINE.md` — metrics and alerts
- `server/src/main/java/odm/clarity/woleh/ws/TransitWebSocketHandler.java`
- `server/src/main/java/odm/clarity/woleh/places/MatchingService.java`
- `server/src/main/java/odm/clarity/woleh/subscription/EntitlementService.java`
