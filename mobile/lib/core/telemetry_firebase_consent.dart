import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics.dart';
import 'telemetry_consent.dart';

/// Applies [FirebaseAnalytics.setConsent] for GA4 consent mode (analytics storage).
///
/// Call after [Firebase.initializeApp] when [Firebase.apps] is non-empty.
Future<void> applyFirebaseProductAnalyticsConsent(bool granted) async {
  if (!kFirebaseAnalyticsEnabled || Firebase.apps.isEmpty) return;
  try {
    await FirebaseAnalytics.instance.setConsent(
      analyticsStorageConsentGranted: granted,
      adStorageConsentGranted: false,
    );
  } catch (e, st) {
    debugPrint('applyFirebaseProductAnalyticsConsent failed: $e\n$st');
  }
}

/// Syncs consent mode from [SharedPreferences] (used at startup).
Future<void> syncFirebaseProductAnalyticsConsentFromPrefs(
  SharedPreferences prefs,
) async {
  if (!kFirebaseAnalyticsEnabled || Firebase.apps.isEmpty) return;
  if (kSkipTelemetryConsentPrompt) {
    await applyFirebaseProductAnalyticsConsent(true);
    return;
  }
  final v = prefs.getBool(kTelemetryProductAnalyticsConsentKey);
  if (v == null) {
    await applyFirebaseProductAnalyticsConsent(false);
  } else {
    await applyFirebaseProductAnalyticsConsent(v);
  }
}
