# Woleh mobile

Flutter client for **Woleh** (transit / live location). Dart package **`odm_clarity_woleh_mobile`**; Android and iOS bundle id **`odm.clarity.woleh_mobile`**.

Monorepo context, API env vars, and staging deploy: [root `README.md`](../README.md). API shapes: [`docs/API_CONTRACT.md`](../docs/API_CONTRACT.md).

## Prerequisites

- **Flutter** SDK matching `environment.sdk` in [`pubspec.yaml`](pubspec.yaml) (currently **Dart ^3.8.1**).
- **JDK17+** and a running **Woleh API** for full app flows (see root README — local Postgres + `./gradlew bootRun`, or staging).

## Setup

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Regenerate Riverpod/part files after changing `@riverpod` or other codegen targets.

## Run

Default **`API_BASE_URL`** is **`http://10.0.2.2:8080`** (Android emulator → host). **iOS Simulator** usually needs the host loopback instead, for example:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

**Physical device** on the same Wi‑Fi as the machine running the API:

```bash
flutter run --dart-define=API_BASE_URL=http://<your-lan-ip>:8080
```

The WebSocket client derives its URL from **`API_BASE_URL`** (same `dart-define`).

### Staging API

Example (matches the repo **Mobile — staging** run configuration):

```bash
flutter run \
  --dart-define=API_BASE_URL=https://woleh.okaidarkomorgan.com \
  --dart-define=OSM_TILE_URL_TEMPLATE=https://tile.openstreetmap.org/{z}/{x}/{y}.png
```

**Release to testers:** [`scripts/bump_version.sh`](scripts/bump_version.sh) bumps `pubspec.yaml` `+build`; [`scripts/deploy_staging_fad.sh`](scripts/deploy_staging_fad.sh) builds with the same defines and uploads to **Firebase App Distribution** (`FAD_GROUPS` and `firebase-tools` required; see script header for iOS signing).

**Android release signing:** add `android/key.properties` from [`android/key.properties.example`](android/key.properties.example) and a `.jks` / `.keystore` next to it (or set an absolute `storeFile`). CI can use the same four values via `WOLEH_KEYSTORE_PATH`, `WOLEH_KEYSTORE_PASSWORD`, `WOLEH_KEY_ALIAS`, and `WOLEH_KEY_PASSWORD`. Without them, release builds still succeed but use **debug** signing (Gradle warns).

### Map tiles

Default tiles use the public OSM template. For the optional local tile server in [`server/docker-compose.yml`](../server/docker-compose.yml) (port **8088** on the host), pass **`OSM_TILE_URL_TEMPLATE`** — see comments in [`lib/shared/location_map.dart`](lib/shared/location_map.dart).

## Push notifications (optional)

FCM is **off** unless you opt in at compile time:

```bash
flutter run --dart-define=WOLEH_PUSH_ENABLED=true
```

Requires a configured **Firebase** project and platform files (e.g. Android `google-services.json`). Without **`WOLEH_PUSH_ENABLED`**, push code is not initialized.

## Crashlytics and Performance (Phase 2)

By default the app initializes **Firebase** when **push** is enabled, when **Firebase monitoring** is enabled, or when **product analytics** is enabled (see [`lib/core/firebase_monitoring.dart`](lib/core/firebase_monitoring.dart)). That enables **Crashlytics** (fatal Flutter/async errors) and **Performance Monitoring**:

- **HTTP:** [`FirebasePerformanceInterceptor`](lib/core/firebase_performance_dio.dart) on the API `Dio` clients (including token refresh).
- **Custom traces:** `ws_transit_connect` (WebSocket until first frame/message), `map_home_first_frame` (map screen first frame).

**Opt out** of monitoring (no Crashlytics/Performance; Firebase still initializes if push or analytics need it):

```bash
flutter run --dart-define=WOLEH_FIREBASE_MONITORING=false
```

If **`WOLEH_FIREBASE_MONITORING`** is true but **`google-services`** / **`GoogleService-Info.plist`** are missing or invalid, `Firebase.initializeApp` fails gracefully and the app still runs.

**Release health** in the Firebase console uses the app **version** and **build** from [`pubspec.yaml`](pubspec.yaml) (`version:` / `+` build number) and standard Android/iOS build metadata.

## Sentry (errors and HTTP performance)

Optional second channel for crashes and API spans. Configuration lives in [`lib/core/sentry_config.dart`](lib/core/sentry_config.dart); [`main.dart`](lib/main.dart) wraps startup with [`runWithSentryIfConfigured`](lib/core/sentry_config.dart). **Dio** uses [`sentry_dio`](https://pub.dev/packages/sentry_dio) when Sentry is on. **Crashlytics** still receives the same fatals when Firebase monitoring is enabled — error handlers are **chained** in [`firebase_monitoring.dart`](lib/core/firebase_monitoring.dart).

Enable by passing a **DSN** at compile time (same project as the server or a separate mobile project in Sentry):

```bash
flutter run \
  --dart-define=SENTRY_DSN=https://examplePublicKey@o0.ingest.sentry.io/0 \
  --dart-define=SENTRY_ENVIRONMENT=staging \
  --dart-define=SENTRY_TRACES_SAMPLE_RATE=0.2
```

Omit **`SENTRY_DSN`** (default) so the SDK does not start — local dev and CI behave as before.

**Disable** Sentry even if a DSN is baked into a script: `--dart-define=WOLEH_SENTRY=false`.

**User id** in Sentry is set/cleared with the same timing as Firebase Analytics user id ([`AnalyticsIdentitySync`](lib/core/analytics_identity_sync.dart)).

Staging FAD builds: set **`SENTRY_DSN`** (and optionally **`SENTRY_ENVIRONMENT`**, **`SENTRY_TRACES_SAMPLE_RATE`**) in the environment; [`scripts/deploy_staging_fad.sh`](scripts/deploy_staging_fad.sh) forwards them into **`--dart-define`** when present.

## Product analytics (Phase 3)

**Firebase Analytics** is wired through [`WolehAnalytics`](lib/core/analytics.dart) ([`wolehAnalyticsProvider`](lib/core/analytics_provider.dart)). **Screen views** use [`FirebaseAnalyticsObserver`](https://pub.dev/documentation/firebase_analytics/latest/firebase_analytics/FirebaseAnalyticsObserver-class.html) on [`GoRouter`](lib/app/router.dart). **User id** is set from `me.profile.userId` after `GET /me` and cleared on sign-out ([`AnalyticsIdentitySync`](lib/core/analytics_identity_sync.dart)).

**Opt out** of Analytics only (Crashlytics/Performance unchanged; if push and monitoring are both off, Firebase is not initialized and analytics is a no-op):

```bash
flutter run --dart-define=WOLEH_FIREBASE_ANALYTICS=false
```

Event names and parameters: [`docs/ANALYTICS_EVENTS.md`](../docs/ANALYTICS_EVENTS.md). For local validation, use **Firebase DebugView** with a debug build.

## Privacy and consent (Phase 4)

**Product analytics** (events, screen views, optional Analytics user id) is **opt-in** when Firebase is available and **`WOLEH_FIREBASE_ANALYTICS`** is true: users choose on the **phone sign-in** screen (pre-checked box) and the value is stored **on the server** and on-device; it can be changed under **Profile → Privacy** (Product analytics switch). Internally this uses Firebase **Consent Mode** (`analyticsStorageConsentGranted`).

**Crashlytics**, **Performance**, and **Sentry** (when enabled) are **not** gated by product-analytics consent; they follow compile-time flags (**`WOLEH_FIREBASE_MONITORING`**, **`SENTRY_DSN`** / **`WOLEH_SENTRY`**). Describe them in your public privacy policy for regulated regions.

**Tests / CI:** Pre-seed consent or skip telemetry UI:

```bash
flutter test --dart-define=WOLEH_SKIP_TELEMETRY_CONSENT=true
```

**Details:** ATT (iOS), Play/App Store disclosures, GDPR notes — [`docs/PRIVACY_TELEMETRY.md`](../docs/PRIVACY_TELEMETRY.md).

## Checks (CI-aligned)

```bash
cd mobile
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Same steps run in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) on push/PR to `main`.
