/// SharedPreferences key for product (Firebase) analytics opt-in (`true` / `false`).
/// `null` (missing) means the user has not answered the prompt yet.
const kTelemetryProductAnalyticsConsentKey =
    'telemetry.product_analytics_consent_v1';

/// When **true**, consent is always treated as granted (for tests / internal builds).
/// The phone-screen checkbox is hidden. Compile with:
/// `--dart-define=WOLEH_SKIP_TELEMETRY_CONSENT=true`
const kSkipTelemetryConsentPrompt = bool.fromEnvironment(
  'WOLEH_SKIP_TELEMETRY_CONSENT',
  defaultValue: false,
);
