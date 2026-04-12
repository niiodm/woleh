import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'analytics.dart';
import 'push_bootstrap.dart';

/// Opt out of Crashlytics / Performance custom traces with:
/// `--dart-define=WOLEH_FIREBASE_MONITORING=false`
///
/// Default **true** so release builds report crashes and HTTP traces when Firebase is configured.
const kFirebaseMonitoringEnabled = bool.fromEnvironment(
  'WOLEH_FIREBASE_MONITORING',
  defaultValue: true,
);

/// Initializes [Firebase] when push and/or monitoring need it, then wires Crashlytics.
///
/// Call from [main] after [WidgetsFlutterBinding.ensureInitialized]. Safe to call when
/// `google-services` is missing (catch and log).
Future<void> bootstrapFirebaseObservability() async {
  if (!kPushEnabled && !kFirebaseMonitoringEnabled && !kFirebaseAnalyticsEnabled) {
    return;
  }
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e, st) {
    debugPrint('bootstrapFirebaseObservability: Firebase.initializeApp failed: $e\n$st');
    return;
  }
  if (!kFirebaseMonitoringEnabled) {
    return;
  }
  try {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e, st) {
    debugPrint('bootstrapFirebaseObservability: Crashlytics setup failed: $e\n$st');
  }
}

/// True when custom Performance traces (WS, map) should run.
bool get firebaseCustomPerformanceEnabled =>
    kFirebaseMonitoringEnabled && Firebase.apps.isNotEmpty;
