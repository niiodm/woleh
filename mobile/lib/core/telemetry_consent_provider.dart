import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'analytics.dart';
import 'shared_preferences_provider.dart';
import 'telemetry_consent.dart';
import 'telemetry_firebase_consent.dart';

part 'telemetry_consent_provider.g.dart';

/// Stored user choice: `null` = not asked, `true` = allowed, `false` = declined.
@Riverpod(keepAlive: true)
class TelemetryConsent extends _$TelemetryConsent {
  @override
  bool? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    if (kSkipTelemetryConsentPrompt) return true;
    return prefs.getBool(kTelemetryProductAnalyticsConsentKey);
  }

  Future<void> setProductAnalyticsAllowed(bool allowed) async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(kTelemetryProductAnalyticsConsentKey, allowed);
    await applyFirebaseProductAnalyticsConsent(allowed);
    ref.invalidateSelf();
  }
}

/// Whether custom events, user id, and automatic screen views may run.
@Riverpod(keepAlive: true)
bool productAnalyticsConsentGranted(Ref ref) {
  if (!kFirebaseAnalyticsEnabled || Firebase.apps.isEmpty) return false;
  if (kSkipTelemetryConsentPrompt) return true;
  return ref.watch(telemetryConsentProvider) == true;
}
