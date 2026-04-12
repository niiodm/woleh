# SLO baseline (Phase 3 — NFR-1)

This runbook defines **initial latency SLOs** for the Woleh API and how to **measure** them in staging and production. Targets are baselines for iteration; tighten them only after enough traffic exists to make percentiles meaningful.

## 1. Latency targets (p95)

| Endpoint group | p95 target | Primary measurement |
|----------------|------------|---------------------|
| Auth (`POST /api/v1/auth/send-otp`, `POST /api/v1/auth/verify-otp`) | **Under 500 ms** | Spring Boot `http.server.requests` (Micrometer), filtered by `uri` |
| Place list reads (`GET /api/v1/me/places/watch`, `GET /api/v1/me/places/broadcast`) | **Under 200 ms** | `http.server.requests` |
| Place list writes (`PUT …/watch`, `PUT …/broadcast`) including match evaluation | **Under 500 ms** | `http.server.requests` for the PUT; **`woleh.match.evaluation`** timer for server-side intersection work |
| WebSocket handshake (upgrade to `/ws/**`) | **Under 300 ms** | `http.server.requests` on the upgrade request where applicable; supplement with **`TransitWebSocketHandler`** connect logs and infrastructure RTT |

**Notes**

- **Auth** latency is driven by OTP issuance, persistence, and (in production) the SMS provider. Do not use `woleh.match.evaluation` for auth; that timer covers match scans only (`MatchingService`).
- **Match dispatch** is O(n) over active lists in v1; the `woleh.match.evaluation` timer records that work. A healthy system shows PUT p95 within SLO while timer p95 stays bounded; if timer grows while PUT stays flat, work may be shifting off the request thread—still investigate.
- **WebSocket** end-to-end “time to first frame” may need client-side or synthetic probes; server-side handshake duration is a proxy.

## 2. Metrics configuration

Percentile histograms for HTTP latency are enabled in `server/src/main/resources/application.yml`:

```yaml
management:
  metrics:
    distribution:
      percentiles-histogram:
        "[http.server.requests]": true
```

Without this, Prometheus cannot derive reliable p95/p99 from buckets. Custom meters (WS sessions, place-list PUTs, match evaluation, API errors) are registered in application code; see `MetricsIntegrationTest` for names.

**Expose metrics safely:** In production and staging, use `management.server.port` (separate from the public API port) and firewall rules so `/actuator/metrics` and `/actuator/prometheus` are not internet-routable. The **`staging`** profile sets port **8081** in [`application-staging.yml`](../../server/src/main/resources/application-staging.yml); Caddy proxies only the API port. Staging Prometheus scrapes `http://api:8081/actuator/prometheus` on the Docker network with HTTP Basic (see [`deploy/staging/prometheus.yml`](../../deploy/staging/prometheus.yml) and [`deploy/staging/docker-compose.yml`](../../deploy/staging/docker-compose.yml)).

## 3. Querying baselines

Assume the management base URL is reachable (locally often the same host as the API, e.g. `http://localhost:8080` per `server/api-tests/http-client.env.json`).

### 3.1 Actuator (raw meter inspection)

- **HTTP server requests** (names and tags vary slightly by Boot version):

  `GET /actuator/metrics/http.server.requests`

- **Filter by URI** (example: watch list read):

  `GET /actuator/metrics/http.server.requests?tag=uri:/api/v1/me/places/watch`

Repeat for `send-otp`, `verify-otp`, broadcast/watch PUTs as needed. The JSON response includes available statistic keys when percentiles are published.

### 3.2 Prometheus

Scrape `GET /actuator/prometheus` from the management port.

**Example (p95 of HTTP latency by URI)** — adjust metric name and labels to match your scrape (`http_server_requests_seconds_bucket` is typical for Micrometer’s Prometheus registry):

```promql
histogram_quantile(
  0.95,
  sum by (le, uri) (
    rate(http_server_requests_seconds_bucket{application="woleh"}[5m])
  )
)
```

**Match evaluation (server timer):**

```promql
histogram_quantile(
  0.95,
  sum by (le) (
    rate(woleh_match_evaluation_seconds_bucket[5m])
  )
)
```

(Exact `_bucket` suffix and label set depend on export; discover names from `/actuator/prometheus`.)

**Active WebSocket sessions (gauge):**

```promql
woleh_ws_sessions_active
```

## 4. Alerting policy (recommended)

| Condition | Action |
|-----------|--------|
| **p95** for any **in-scope URI group** breaches its target for **5 consecutive minutes** | Page on-call |
| **Error rate** (4xx/5xx from `woleh.api.errors` or HTTP status tags) spikes correlated with deploy | Roll back or scale; see `INCIDENT_RESPONSE.md` |
| **`woleh.ws.sessions.active`** grows monotonically over hours without traffic increase | Treat as session leak; see `INCIDENT_RESPONSE.md` §1 |

Tune windows (e.g. 5m vs 15m) once burn-rate and noise levels are known.

## 5. Definition of done (SLO artifact)

- [ ] Dashboards in your observability stack plot p95 for auth, place-list read/write, and match timer.
- [ ] Alerts encode the 5-minute breach rule (or stricter) for production.
- [ ] Management endpoints are not publicly exposed without authentication/network controls.

## 6. References

- `docs/PHASE_3_IMPLEMENTATION.md` — Phase 3 Step 4.1
- `server/src/main/resources/application.yml` — `management.metrics`, Actuator exposure
- `server/src/test/java/odm/clarity/woleh/api/MetricsIntegrationTest.java` — custom meter names
