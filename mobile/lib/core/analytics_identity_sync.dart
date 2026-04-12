import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_provider.dart';
import 'auth_state.dart';
import 'telemetry_consent_provider.dart';
import '../features/me/presentation/me_notifier.dart';

/// Sets [Firebase Analytics user id](https://support.google.com/analytics/answer/9213390)
/// from `GET /me` after sign-in and clears it on sign-out.
class AnalyticsIdentitySync extends ConsumerWidget {
  const AnalyticsIdentitySync({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authStateProvider, (_, next) {
      if (next.valueOrNull == null) {
        unawaited(ref.read(wolehAnalyticsProvider).setUserId(null));
      }
    });
    ref.listen(meNotifierProvider, (_, next) {
      final snap = next.valueOrNull;
      if (snap == null) return;
      final uid = snap.me.profile.userId;
      unawaited(ref.read(wolehAnalyticsProvider).setUserId(uid));
      unawaited(
        ref.read(telemetryConsentProvider.notifier).setProductAnalyticsAllowed(
              snap.me.profile.productAnalyticsConsent,
            ),
      );
    });
    return child;
  }
}
