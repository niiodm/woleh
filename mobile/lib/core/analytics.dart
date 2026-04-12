import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';

/// Opt out of product analytics with `--dart-define=WOLEH_FIREBASE_ANALYTICS=false`.
///
/// Default **true** when Firebase is configured; calls no-op when disabled or
/// Firebase failed to initialize.
const kFirebaseAnalyticsEnabled = bool.fromEnvironment(
  'WOLEH_FIREBASE_ANALYTICS',
  defaultValue: true,
);

/// True when Firebase Analytics API calls should run.
bool get wolehAnalyticsRuntimeEnabled =>
    kFirebaseAnalyticsEnabled && Firebase.apps.isNotEmpty;

/// [NavigatorObserver]s for automatic `screen_view` events (GoRouter route names).
List<NavigatorObserver> firebaseAnalyticsNavigatorObservers() {
  if (!wolehAnalyticsRuntimeEnabled) {
    return const [];
  }
  return [
    FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
  ];
}

/// Product analytics facade (Firebase today; swappable implementation).
abstract class WolehAnalytics {
  Future<void> logEvent(String name, [Map<String, Object>? parameters]);

  Future<void> setUserId(String? id);

  Future<void> logButtonTapped(String buttonId, {required String screenName});
}

class NoOpWolehAnalytics implements WolehAnalytics {
  const NoOpWolehAnalytics();

  @override
  Future<void> logEvent(String name, [Map<String, Object>? parameters]) async {
    if (kDebugMode) {
      debugPrint('[WolehAnalytics] logEvent: $name ${parameters ?? {}}');
    }
  }

  @override
  Future<void> setUserId(String? id) async {
    if (kDebugMode) {
      debugPrint('[WolehAnalytics] setUserId: ${id ?? '(cleared)'}');
    }
  }

  @override
  Future<void> logButtonTapped(String buttonId, {required String screenName}) async {
    return logEvent('button_tapped', {
      'button_id': buttonId,
      'screen_name': screenName,
    });
  }
}

class FirebaseWolehAnalytics implements WolehAnalytics {
  FirebaseWolehAnalytics(this._fa);

  final FirebaseAnalytics _fa;

  @override
  Future<void> logEvent(String name, [Map<String, Object>? parameters]) async {
    if (kDebugMode) {
      debugPrint('[WolehAnalytics] logEvent: $name ${parameters ?? {}}');
    }
    try {
      await _fa.logEvent(name: name, parameters: parameters);
    } catch (e, st) {
      debugPrint('WolehAnalytics.logEvent failed: $e\n$st');
    }
  }

  @override
  Future<void> setUserId(String? id) async {
    if (kDebugMode) {
      debugPrint('[WolehAnalytics] setUserId: ${id ?? '(cleared)'}');
    }
    try {
      await _fa.setUserId(id: id);
    } catch (e, st) {
      debugPrint('WolehAnalytics.setUserId failed: $e\n$st');
    }
  }

  @override
  Future<void> logButtonTapped(String buttonId, {required String screenName}) {
    return logEvent('button_tapped', {
      'button_id': buttonId,
      'screen_name': screenName,
    });
  }
}
