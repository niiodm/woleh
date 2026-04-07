# ADR 0005: Payment via local provider in secure WebView

## Status

Accepted

## Context

Woleh needs paid subscriptions in **Ghana** using a **local** payment provider. Native SDKs may be unavailable or undesirable for v1; we still want to avoid handling card or mobile-money PANs on our servers.

## Decision

1. **Provider:** Integrate a **Ghana-local** payment provider chosen at implementation time (specific vendor is an implementation detail; must support redirect/hosted checkout patterns).
2. **Client UX:** The mobile app opens a **secure WebView** (or platform equivalent: `SFSafariViewController` / Chrome Custom Tabs if required by provider policy) loading **only HTTPS URLs** returned by our API or the provider.
3. **Checkout flow:**
   - Client calls **`POST /api/v1/subscription/checkout`** (or named equivalent) with `planId` and receives **`checkoutUrl`** and a **`sessionId`** (or provider reference) from our backend.
   - Backend creates a **server-side payment session** with the provider (amount, currency GHS, return URLs, metadata linking `userId` + `planId`).
   - User completes payment in the provider’s **hosted** UI inside the WebView.
   - Completion is signaled by **provider webhook** to our backend (primary) and/or **redirect** to an app deep link (`woleh://…` or App Links) with success/failure query params (secondary, for UX).
4. **PCI:** Woleh servers and app **never** collect or store raw card numbers; only tokens/session ids from the provider.
5. **Entitlements:** Activate paid **permissions** only after server confirms payment (webhook or verified redirect callback), not when the WebView merely opens.

## Consequences

**Positive:** Matches common local-provider patterns; minimizes PCI scope; works without a native SDK in v1.

**Negative:** WebView UX and redirect handling must be tested per OS; deep-link edge cases need QA.

## Date

2026-04-06
