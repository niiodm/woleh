/// SharedPreferences key for product (Firebase) analytics opt-in (`true` / `false`).
/// `null` (missing) means the user has not answered the prompt yet.
const kTelemetryProductAnalyticsConsentKey =
    'telemetry.product_analytics_consent_v1';

/// When **true**, the first-run analytics consent dialog is skipped and consent is
/// treated as granted (for tests / internal builds). Compile with:
/// `--dart-define=WOLEH_SKIP_TELEMETRY_CONSENT=true`
const kSkipTelemetryConsentPrompt = bool.fromEnvironment(
  'WOLEH_SKIP_TELEMETRY_CONSENT',
  defaultValue: false,
);
