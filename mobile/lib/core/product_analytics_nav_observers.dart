import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'analytics.dart';
import 'telemetry_consent_provider.dart';

part 'product_analytics_nav_observers.g.dart';

/// [NavigatorObserver]s for automatic `screen_view` events when product analytics consent is granted.
@Riverpod(keepAlive: true)
List<NavigatorObserver> productAnalyticsNavigatorObservers(Ref ref) {
  if (!ref.watch(productAnalyticsConsentGrantedProvider)) {
    return const [];
  }
  if (!kFirebaseAnalyticsEnabled || Firebase.apps.isEmpty) {
    return const [];
  }
  return [
    FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
  ];
}
