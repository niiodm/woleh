# Privacy, telemetry, and consent (mobile)

This document complements [`docs/MONITORING_AND_ANALYTICS_PLAN.md`](MONITORING_AND_ANALYTICS_PLAN.md) and the mobile [README](../mobile/README.md).

## What the app can collect

| Signal | Controlled by | Notes |
|--------|----------------|--------|
| **Product analytics** (Firebase Analytics / GA4: events, screen views, optional user id) | In-app consent + `WOLEH_FIREBASE_ANALYTICS` | [Consent Mode](https://firebase.google.com/docs/analytics/configure-data-collection) via `setConsent`. |
| **Crash reports** (Crashlytics) | `WOLEH_FIREBASE_MONITORING` | Separate from product analytics; align with your privacy policy. |
| **Performance traces** (HTTP, custom) | `WOLEH_FIREBASE_MONITORING` | Same Firebase project as Crashlytics. |
| **Push (FCM)** | `WOLEH_PUSH_ENABLED` | Device token registration; separate from GA4. |

## GDPR / CCPA

- **Product analytics** uses an **opt-in** first-run dialog when Firebase is initialized and `WOLEH_FIREBASE_ANALYTICS` is true. Choice is stored under `telemetry.product_analytics_consent_v1` and can be changed in **Profile → Privacy**.
- **Crashlytics / Performance** remain **compile-time** toggles for engineering; document their use in your public privacy policy if you ship to regulated regions.
- For broad EU/US launches, add or extend a **privacy policy** and, if required, a **Data Processing Agreement** with Google (Firebase).

## iOS: App Tracking Transparency (ATT)

- **Firebase Analytics** in typical app-analytics configuration **does not** require the ATT prompt by itself; ATT applies when you access the **IDFA** for cross-app tracking (often ads).
- If you later add **Google Mobile Ads** or other SDKs that use IDFA, add [`NSUserTrackingUsageDescription`](https://developer.apple.com/documentation/bundleresources/information_property_list/nsusertrackingusagedescription) to `Info.plist` and request permission with `ATTrackingManager` only when needed.
- App Store **Privacy Nutrition Labels** should reflect data collected by Firebase; see [Firebase + App Store](https://firebase.google.com/docs/ios/app-store-data-collection).

## Android

- Declare data safety in the Play Console to match Firebase/Crashlytics usage; see [Google’s guidance](https://support.google.com/googleplay/android-developer/answer/10787469).

## Local development / CI

- Disable analytics: `--dart-define=WOLEH_FIREBASE_ANALYTICS=false`
- Skip the consent dialog in tests: `--dart-define=WOLEH_SKIP_TELEMETRY_CONSENT=true` (or pre-seed SharedPreferences with `telemetry.product_analytics_consent_v1`)
