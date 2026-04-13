import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'analytics.dart';
import 'telemetry_consent_provider.dart';

part 'product_analytics_nav_observers.g.dart';

/// Forwards navigation events to [FirebaseAnalyticsObserver] only when product
/// analytics consent is currently granted.
///
/// The [GoRouter] is configured with a **stable** observer list (this instance
/// is created once). Consent is read on each navigation callback so saving
/// consent on the phone sign-in screen does not swap the observer list, which
/// would recreate [GoRouter] and reset navigation (dropping the in-flight OTP
/// transition).
class ConsentAwareFirebaseAnalyticsObserver extends NavigatorObserver {
  ConsentAwareFirebaseAnalyticsObserver(this._ref)
      : _delegate = FirebaseAnalyticsObserver(
          analytics: FirebaseAnalytics.instance,
        );

  final Ref _ref;
  final FirebaseAnalyticsObserver _delegate;

  bool get _shouldLog {
    if (!kFirebaseAnalyticsEnabled || Firebase.apps.isEmpty) return false;
    return _ref.read(productAnalyticsConsentGrantedProvider);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_shouldLog) _delegate.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_shouldLog) _delegate.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_shouldLog) {
      _delegate.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    }
  }
}

/// [NavigatorObserver]s for automatic `screen_view` events when product analytics
/// consent is granted (checked at navigation time, not when this provider runs).
@Riverpod(keepAlive: true)
List<NavigatorObserver> productAnalyticsNavigatorObservers(Ref ref) {
  if (!kFirebaseAnalyticsEnabled || Firebase.apps.isEmpty) {
    return const [];
  }
  return [ConsentAwareFirebaseAnalyticsObserver(ref)];
}
