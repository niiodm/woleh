import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Product analytics consent is captured on the **phone sign-in** screen (pre-checked
/// checkbox) and from **Profile → Privacy**; logged-in devices sync from `GET /me`.
///
/// Crashlytics / Performance remain governed by [WOLEH_FIREBASE_MONITORING]; see README.
class TelemetryConsentGate extends ConsumerWidget {
  const TelemetryConsentGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => child;
}
