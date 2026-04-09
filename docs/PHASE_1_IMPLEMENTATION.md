# Phase 1 — Implementation breakdown (codable steps)

This document turns [PRD.md](./PRD.md) §10 **Phase 1 — Plans** into ordered, implementable work. **Exit criterion:** a paid plan unlocks gated features end-to-end — a user subscribes, the server confirms payment, and `GET /me` returns paid-tier permissions that change what the mobile app shows.

**References:** [ARCHITECTURE.md](./ARCHITECTURE.md), [API_CONTRACT.md](./API_CONTRACT.md), [PRD.md](./PRD.md) §13.1–§13.6, [ADR 0005](./adr/0005-payment-checkout-webview.md) (payment WebView), [ADR 0004](./adr/0004-jurisdiction-ghana.md) (Ghana / GHS), [Phase 0 implementation](./PHASE_0_IMPLEMENTATION.md).

### Locked identifiers (carry-over from Phase 0)

| Artifact | Value |
|----------|--------|
| **Server base package** | `odm.clarity.woleh` |
| **Flutter package** | `odm_clarity_woleh_mobile` |
| **Riverpod** | Codegen on — `@riverpod` / `@Riverpod` + `*.g.dart` |
| **Currency** | **GHS** — all price amounts stored and returned in minor units (pesewas) |
| **Grace period** | **7 calendar days** after subscription `currentPeriodEnd` |

---

## 1. Scope

| In scope (Phase 1) | Deferred |
|--------------------|----------|
| DB schema: `plans`, `subscriptions`, `payment_sessions` tables | Place-name lists (`/me/places/*`) — Phase 2 |
| `GET /api/v1/subscription/plans` (seeded, real response) | WebSocket `/ws/v1/transit` — Phase 2 |
| Permission computation from live subscription (replaces Phase 0 hard-coded free tier) | Refresh tokens / re-auth policy — still deferred |
| Grace period enforcement (7 days) | Rate limiting beyond OTP — Phase 3 |
| `POST /api/v1/subscription/checkout` — returns `checkoutUrl` from provider | Real SMS provider in production — ongoing |
| Payment provider adapter interface + stub | Multi-product / multi-tenant on shared API (requires ADR) |
| Webhook / server-side payment confirmation endpoint | Push notifications for subscription expiry — Phase 3 |
| `GET /api/v1/subscription/status` | Partial refunds / cancellation flows |
| `GET /me` updated to reflect real subscription state | |
| Mobile: Plans screen with plan cards (permissions + pricing in GHS) | |
| Mobile: Checkout WebView flow + deep-link return | |
| Mobile: Subscription status on home / profile | |
| Mobile: Permission-aware router gates + conditional UI | |
| `.http` collection updated for Phase 1 flows | |

**Optional within Phase 1** (recommended but not required for exit criterion): Expose subscription status banner on the home screen showing tier and `currentPeriodEnd` when the subscription is active.

---

## 2. Server (Spring Boot)

### Step 2.1 — Subscription schema ✅

Add three new tables via Flyway migration:

- **`plans`**: `id` (PK), `plan_id` (unique string, e.g. `woleh_paid_monthly`), `display_name`, `permissions_granted` (JSON array of permission strings), `price_amount_minor` (integer, pesewas), `price_currency` (varchar, `GHS`), `place_watch_max` (int), `place_broadcast_max` (int), `active` (boolean).
- **`subscriptions`**: `id`, `user_id` (FK → `users`), `plan_id` (FK → `plans`), `status` (`active` | `expired` | `cancelled`), `current_period_start`, `current_period_end`, `grace_period_end` (= `current_period_end + 7 days`), `provider_subscription_id` (nullable, opaque), `created_at`, `updated_at`.
- **`payment_sessions`**: `id`, `user_id` (FK), `plan_id` (FK), `session_id` (unique, server-generated), `provider_reference` (nullable), `status` (`pending` | `completed` | `failed` | `expired`), `checkout_url`, `expires_at`, `created_at`.

Seed the v1 **plans** in a separate Flyway migration (data migration):
- `woleh_free` — `woleh.account.profile`, `woleh.plans.read`, `woleh.place.watch`; watch cap 5; broadcast cap 0; price 0.
- `woleh_paid_monthly` — all four permissions; watch cap 50; broadcast cap 50; price in GHS (exact amount TBD; use a placeholder, e.g. 999 pesewas = GHS 9.99, until confirmed with product).

**Implementation:** Flyway **`V3__subscriptions.sql`** (three tables); **`V4__seed_plans.sql`** (two plan rows); JPA entities `Plan`, `Subscription`, `PaymentSession`; Spring Data repositories `PlanRepository`, `SubscriptionRepository`, `PaymentSessionRepository`.

**Done when:** migrations apply cleanly; entities map to tables; a `PlanRepository.findByPlanId("woleh_paid_monthly")` round-trip passes in a test.

---

### Step 2.2 — Permission service (real subscription-backed entitlements) ✅

Replace the Phase 0 hard-coded free-tier block in `MeController` with a dedicated `EntitlementService`:

- **`EntitlementService.computeEntitlements(userId)`**: load the user's most recent `active` (or in-grace) subscription → look up the plan → return permissions, tier, limits, subscription status. Fall back to the `woleh_free` plan if no active subscription exists.
- **Grace logic:** if `now` is after `current_period_end` but before `grace_period_end`, keep the subscription's plan permissions (grace period per [PRD.md](./PRD.md) §13.6). After `grace_period_end`, enforce free-tier defaults.
- **`tier`** field: `"paid"` when the active plan is non-free; `"free"` otherwise.
- The `subscription` block in the response should reflect real DB state: `status`, `currentPeriodEnd` (ISO-8601 UTC), `inGracePeriod` flag.

**Implementation:** `EntitlementService` (Spring `@Service`); `Entitlements` record (permissions list, tier, limits, subscription block); `MeController` delegates to `EntitlementService`; update `MeResponse` if needed so `subscription.currentPeriodEnd` can be non-null; update `MeIntegrationTest` for new structure.

**Done when:** `GET /me` for a user with no subscription still returns free-tier; a user with a seeded `active` subscription returns paid-tier permissions.

---

### Step 2.3 — `GET /api/v1/subscription/plans`

Implement the public plan catalog endpoint per [API_CONTRACT.md](./API_CONTRACT.md) §6.5:

- No auth required.
- Query `plans` table where `active = true`; return array ordered deterministically (e.g. by `price_amount_minor` ascending so free appears first).
- Response shape per contract: `planId`, `displayName`, `permissionsGranted`, `limits`, `price { amountMinor, currency }`.
- Include the free tier plan in the list so the client can display "what you get for free" alongside the paid option.

**Implementation:** `SubscriptionController` at `/api/v1/subscription`; `PlanResponse` DTO; `PlanService.listActivePlans()`; `SecurityConfig` updated to permit `/api/v1/subscription/plans` without auth; tests `PlansIntegrationTest` (unauthenticated call returns 200 + both plans).

**Done when:** `GET /api/v1/subscription/plans` returns both seeded plans without a token; shapes match API contract.

---

### Step 2.4 — Payment provider adapter interface

Define a provider-agnostic interface behind which any Ghana-local provider (Paystack, Hubtel, etc.) can be plugged:

```java
public interface PaymentProviderAdapter {
    CheckoutSession createCheckoutSession(
        String userId,
        String planId,
        long amountMinor,
        String currency,
        String returnUrl,
        String webhookRef
    );
    boolean verifyWebhookSignature(String rawBody, String providerHeader);
    WebhookEvent parseWebhookEvent(String rawBody);
}
```

- `CheckoutSession` carries `checkoutUrl`, `providerReference`, `expiresAt`.
- `WebhookEvent` carries `type` (`payment_success` | `payment_failed`), `providerReference`, and any metadata needed to look up the `PaymentSession`.
- Provide **`StubPaymentProviderAdapter`** (active by default in `dev` profile): generates a `checkoutUrl` pointing at a local `GET /api/v1/dev/checkout-stub?sessionId=...&result=success|failure` endpoint that simulates a provider redirect; no signature verification; `WebhookEvent` pre-populated from query params.

**Implementation:** `PaymentProviderAdapter` interface; `StubPaymentProviderAdapter` (`@Profile("dev")`); `PaymentProviderProperties` (`woleh.payment.*`) for future real-provider credentials; `GlobalExceptionHandler` updated with `PaymentException → 400/402`.

**Done when:** a checkout session can be started in `dev` using the stub; the stub's local redirect simulates success/failure.

---

### Step 2.5 — `POST /api/v1/subscription/checkout`

Implement per [API_CONTRACT.md](./API_CONTRACT.md) §6.6:

- Requires auth + `woleh.plans.read` permission.
- Validate `planId` exists and is active; reject free plan (no checkout for free tier → `400`).
- Check for an existing `pending` session for the same user+plan that hasn't expired — return it rather than creating a duplicate (idempotency).
- Call `PaymentProviderAdapter.createCheckoutSession(...)` to obtain `checkoutUrl`.
- Persist `PaymentSession` with `status: pending`.
- Return `{ checkoutUrl, sessionId, expiresAt }`.
- `returnUrl` embedded in the session should be the app deep link (`woleh://subscription/result`) so the provider can redirect back after payment.

**Implementation:** `SubscriptionController.checkout(...)` (`POST /api/v1/subscription/checkout`); `CheckoutRequest` / `CheckoutResponse` DTOs; `SubscriptionService.initiateCheckout(...)`; `PaymentSessionRepository`; tests `CheckoutIntegrationTest` (missing permission → 403, unknown plan → 400, valid → 200 with `checkoutUrl`).

**Done when:** a `dev`-profile checkout returns a valid stub URL; 403 is returned for users missing `woleh.plans.read`.

---

### Step 2.6 — Payment webhook / callback

Handle the provider's server-to-server confirmation that a payment completed:

- Expose **`POST /api/v1/webhooks/payment`** (permit without auth in security config; authenticate via provider signature instead).
- Call `PaymentProviderAdapter.verifyWebhookSignature(rawBody, header)` — reject with `400` on mismatch.
- Parse `WebhookEvent`; look up `PaymentSession` by `providerReference`.
- On `payment_success`:
  - Mark `PaymentSession.status = completed`.
  - Create or update `Subscription` for the user: `status = active`, `currentPeriodStart = now`, `currentPeriodEnd = now + plan period` (e.g. 30 days for monthly), `gracePeriodEnd = currentPeriodEnd + 7 days`.
  - The next `GET /me` call automatically picks up paid entitlements via `EntitlementService`.
- On `payment_failed`: mark session `failed`; no subscription change.
- Return `200` in all valid-signature cases (provider must not retry on business-logic failures; log and alert).

**Implementation:** `WebhookController` at `/api/v1/webhooks`; `SubscriptionService.confirmPayment(...)`; `SecurityConfig` permits `/api/v1/webhooks/**` without JWT (signature-checked instead); `WebhookController` reads raw body with `@RequestBody String`; `StubPaymentProviderAdapter.verifyWebhookSignature` always returns `true` in `dev`; tests `WebhookIntegrationTest` (valid success event activates subscription, bad signature → 400).

**Done when:** calling the stub's local redirect endpoint (`/api/v1/dev/checkout-stub?result=success`) triggers webhook logic and `GET /me` subsequently returns `tier: paid`.

---

### Step 2.7 — `GET /api/v1/subscription/status`

Implement detailed subscription status per API contract §5 permission matrix:

- Requires auth + `woleh.account.profile`.
- Return the full entitlements block (same shape as in `GET /me`) plus any extra billing fields useful for the status screen (e.g. `planDisplayName`, `providerSubscriptionId` if present).
- Reuse `EntitlementService.computeEntitlements(userId)`.

**Implementation:** `SubscriptionController.status(...)` (`GET /api/v1/subscription/status`); `SubscriptionStatusResponse` DTO (extends or wraps `Entitlements`); tests `SubscriptionStatusIntegrationTest`.

**Done when:** a paid user gets their subscription details; a free user gets the free-tier stub.

---

### Step 2.8 — Dev checkout stub endpoint

Add a **`dev`-only** endpoint that simulates a payment-provider redirect, enabling end-to-end testing in development without a real provider:

- `GET /api/v1/dev/checkout-stub?sessionId=...&result=success|failure`
- Permitted without auth; guarded by `@Profile("dev")`.
- Looks up `PaymentSession` by `sessionId`; calls `SubscriptionService.confirmPayment(...)` for `success` or marks session `failed` for `failure`.
- Responds with an app deep-link redirect (`woleh://subscription/result?status=success|failure&sessionId=...`) so Flutter's WebView can intercept it.

**Implementation:** `DevController` (`@Profile("dev")`); only available in `dev` profile; integration test `DevCheckoutStubTest` confirming the subscription activates and the redirect location header is correct.

**Done when:** the full loop in `dev` works: send checkout → open stub URL → stub activates subscription → `GET /me` returns paid tier.

---

### Step 2.9 — Tests and API artifacts

- **Unit tests:** `EntitlementServiceTest` — free tier when no subscription; active paid subscription; subscription in grace period; subscription past grace period (reverts to free).
- **Integration tests:** as noted in steps 2.1–2.8 above.
- **`server/api-tests/phase1.http`**: list plans → checkout (dev) → open stub URL → `GET /me` showing paid tier → `GET /subscription/status`; include `@sessionId` variable for chaining.
- Update **`http-client.env.json`** with any new Phase 1 environment variables.

**Done when:** CI is green; `.http` collection documents the full paid-plan flow for manual QA.

---

## 3. Mobile (Flutter)

### Step 3.1 — Permission provider + router gates

Build the permission infrastructure that Phase 1 gating depends on:

- **`permissionsProvider`**: derived from `meNotifierProvider`; exposes the `List<String>` of effective permissions. Stays in sync automatically when `meNotifierProvider` reloads (e.g. after checkout).
- **`hasPermissionProvider(String permission)`**: family provider returning `bool`; used in route guards and conditional widgets.
- **`PlansScreen`** route: accessible to all authenticated users (everyone can view plans).
- **Gated routes** (placeholder screens acceptable for Phase 1): protect `/broadcast` (or equivalent) behind `woleh.place.broadcast`; redirect to an "upgrade required" screen or the plans screen when permission is absent. Use `GoRouter`'s `redirect` callback — do not gate inside `builder`.

**Implementation:** `permission_provider.dart` (keepAlive, derived from `meNotifierProvider`); `PermissionGuard` helper (extract from router); update `router.dart` with plans and upgrade-redirect routes; widget tests verify that an authenticated user missing `woleh.place.broadcast` is redirected to the plans screen.

**Done when:** a simulated free-tier user cannot navigate to a broadcast-gated route; a paid-tier user can.

---

### Step 3.2 — Plans screen

Display the plan catalog fetched from `GET /api/v1/subscription/plans`:

- **`PlansDto`** / `PlanDto` matching contract §6.5: `planId`, `displayName`, `permissionsGranted`, `limits`, `price { amountMinor, currency }`.
- **`PlansRepository`**: `getPlans()` returning `List<PlanDto>`; `keepAlive` provider.
- **`PlansNotifier`**: async notifier loading plans, exposing `AsyncValue<List<PlanDto>>`.
- **`PlansScreen`**: card per plan; each card shows `displayName`, formatted price (convert `amountMinor` to `GHS X.XX` display; free tier shows "Free"), permissions list as readable strings (map `woleh.place.broadcast` → "Broadcast your route", etc.), and limits (`placeWatchMax`, `placeBroadcastMax`).
- Current plan highlighted (compare against `meNotifierProvider`'s `tier`).
- "Subscribe" CTA on paid plan(s); disabled / "Current plan" on the user's active plan.
- Entry point: add a **Plans** menu item or button on the home screen (e.g. in the AppBar or a profile section).

**Implementation:** `mobile/lib/features/subscription/data/plans_dto.dart`; `mobile/lib/features/subscription/data/plans_repository.dart`; `mobile/lib/features/subscription/presentation/plans_notifier.dart`; `mobile/lib/features/subscription/presentation/plans_screen.dart`; router route `/plans`; widget tests with stub `PlansNotifier` verifying card layout, price format, current-plan highlight.

**Done when:** free-tier user opens Plans screen, sees both plans, paid plan's "Subscribe" button is enabled.

---

### Step 3.3 — Checkout WebView flow

Handle the full checkout lifecycle per [ADR 0005](./adr/0005-payment-checkout-webview.md):

- **`SubscriptionRepository`**: `startCheckout(planId)` calling `POST /api/v1/subscription/checkout`; returns `CheckoutResponse` (`checkoutUrl`, `sessionId`, `expiresAt`).
- **`CheckoutNotifier`**: manages state through `idle → loading → webviewOpen → polling → success | failed`; calls `startCheckout`; after WebView closes, triggers a `meNotifier.refresh()` to re-fetch entitlements.
- **WebView screen** (`CheckoutWebViewScreen`): opens `checkoutUrl` in an in-app WebView (`flutter_inappwebview` or `webview_flutter`); intercepts navigation to `woleh://subscription/result` (deep-link redirect from provider/stub) to detect payment outcome without waiting for the user to close the WebView.
  - On `?status=success`: dismiss WebView, call `meNotifier.refresh()`, navigate to a success/confirmation screen or home.
  - On `?status=failure`: dismiss WebView, show error with retry option.
  - Back/close button: dismiss WebView without changing subscription state; show the plans screen.
- **Deep-link registration:** add `woleh://` custom scheme to Android `AndroidManifest.xml` (`intent-filter`) and iOS `Info.plist` (`CFBundleURLSchemes`) so the OS routes the provider redirect back to the app.
- **Polling fallback** (optional but recommended): if the deep link is not intercepted within a timeout (e.g. 30 s after WebView closes), poll `GET /me` once and show a status message. This guards against webhook delays.

**Add dependency:** `flutter_inappwebview` (or `webview_flutter`) to `pubspec.yaml`.

**Implementation:** `mobile/lib/features/subscription/data/checkout_dto.dart`; `mobile/lib/features/subscription/data/subscription_repository.dart`; `mobile/lib/features/subscription/presentation/checkout_notifier.dart`; `mobile/lib/features/subscription/presentation/checkout_webview_screen.dart`; platform manifest changes; router routes `/checkout/:planId`, `/checkout/result`; widget tests with stub `SubscriptionRepository` covering loading state and error state; WebView intercept logic unit-tested via mock `NavigationDelegate`.

**Done when:** tapping "Subscribe" on the Plans screen opens the WebView with the stub URL; completing the stub flow dismisses the WebView and `GET /me` returns `tier: paid` on home screen.

---

### Step 3.4 — Subscription status on home / profile

Surface subscription state to the user after they return from checkout or on every app open:

- **Home screen** (update existing): add a subscription status row below the tier chip — show plan display name and `currentPeriodEnd` formatted as a human date (e.g. "Renews 7 May 2026") for paid users; show "Free plan · Upgrade" link for free users.
- **Grace period banner**: if `inGracePeriod: true`, show a warning card ("Your subscription has expired — you have X days remaining") with a CTA to the Plans screen.
- `meNotifier.refresh()` is already called after checkout; the home screen rebuilds reactively.
- Pull-to-refresh on home screen already implemented in Phase 0 — no change needed.

**Implementation:** update `home_screen.dart` subscription section; add `SubscriptionStatusCard` widget (`mobile/lib/features/subscription/presentation/subscription_status_card.dart`); widget tests covering paid, free, and grace-period states.

**Done when:** paid user's home screen shows plan name and period end; free user sees upgrade link; grace-period user sees warning.

---

### Step 3.5 — Conditional UI for broadcast gate

Make the broadcast permission gate visible in the app even before Phase 2 builds the actual broadcast feature:

- On the home screen (or a new "Actions" section), render a **"Broadcast your route"** entry:
  - If `woleh.place.broadcast` is present: show as an active button (taps into a placeholder "Coming soon" or the actual broadcast screen in Phase 2).
  - If absent: show as greyed-out with a padlock icon and "Upgrade to unlock" copy tapping to the Plans screen.
- This establishes the permission-aware UI pattern that Phase 2 will complete.

**Implementation:** `PermissionGatedButton` or similar reusable widget in `mobile/lib/shared/`; applied on `HomeScreen`; widget tests: free user sees locked state, paid user sees unlocked state.

**Done when:** permission chip state correctly reflects tier; the locked/unlocked toggle is tested.

---

### Step 3.6 — Tests

- Widget tests for `PlansScreen`: stub notifier, verify card rendering, price formatting, current-plan highlight.
- Widget tests for `CheckoutWebViewScreen`: loading state, error state, stub deep-link interception.
- Widget tests for home screen subscription card: paid / free / grace states.
- Widget tests for `PermissionGatedButton`: locked and unlocked states.
- Unit tests for `EntitlementService` (server side) per §2.9.
- Router redirect tests: free user redirected from broadcast route to plans; paid user allowed through.

**Done when:** CI is green; coverage over all new screens and the permission gate.

---

## 4. Definition of done (Phase 1)

- [ ] `GET /api/v1/subscription/plans` returns seeded free + paid plans; no auth required.
- [ ] `GET /me` reflects real subscription state; free tier by default; paid tier after confirmed webhook.
- [ ] Grace period: subscription past `currentPeriodEnd` but within 7 days keeps paid permissions; after 7 days reverts to free.
- [ ] `POST /api/v1/subscription/checkout` returns a valid (stub) `checkoutUrl`; 403 without auth/permission.
- [ ] Dev checkout stub simulates success/failure and activates/rejects the subscription.
- [ ] Webhook confirms payment → subscription activated → next `GET /me` returns `tier: paid` + `woleh.place.broadcast`.
- [ ] `GET /api/v1/subscription/status` returns subscription details for authenticated users.
- [ ] Mobile Plans screen renders both plans; current plan is highlighted.
- [ ] Tapping "Subscribe" opens the WebView; stub flow completes; home screen updates to paid tier without manual app restart.
- [ ] Broadcast route is gated: free users are redirected to Plans; paid users are allowed through.
- [ ] Grace-period banner is shown when `inGracePeriod: true`.
- [ ] CI passes: server + mobile tests green.
- [ ] `server/api-tests/phase1.http` documents the plans → checkout → activation flow.

---

## 5. Document history

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2026-04-07 | Initial Phase 1 codable breakdown |
| 0.2 | 2026-04-09 | Step 2.1 implemented: V3/V4 migrations, StringListConverter, SubscriptionStatus/PaymentSessionStatus enums, Plan/Subscription/PaymentSession entities, PlanRepository/SubscriptionRepository/PaymentSessionRepository, PlanRepositoryTest (5 tests) |
| 0.3 | 2026-04-09 | Step 2.2 implemented: Entitlements record, EntitlementService (free tier / active / grace / expired logic), MeController updated, EntitlementServiceTest (4 unit tests), MeIntegrationTest extended (3 new paid/grace/expired cases) |

When Phase 1 is complete, update [PRD.md](./PRD.md) phase table to "✅ Complete" and note any deviations (e.g. actual payment provider chosen, any limits adjusted).
