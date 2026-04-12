import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'analytics.dart';

part 'analytics_provider.g.dart';

@Riverpod(keepAlive: true)
WolehAnalytics wolehAnalytics(Ref ref) {
  if (!kFirebaseAnalyticsEnabled || Firebase.apps.isEmpty) {
    return const NoOpWolehAnalytics();
  }
  return FirebaseWolehAnalytics(FirebaseAnalytics.instance);
}
