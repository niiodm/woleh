import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics.dart';
import 'telemetry_consent.dart';
import 'telemetry_consent_provider.dart';

/// First-run dialog for **product analytics** (GDPR/CCPA-style opt-in when Firebase is active).
///
/// Crashlytics / Performance remain governed by [WOLEH_FIREBASE_MONITORING]; see README.
class TelemetryConsentGate extends ConsumerStatefulWidget {
  const TelemetryConsentGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TelemetryConsentGate> createState() =>
      _TelemetryConsentGateState();
}

class _TelemetryConsentGateState extends ConsumerState<TelemetryConsentGate> {
  bool _scheduledPrompt = false;

  @override
  Widget build(BuildContext context) {
    final consent = ref.watch(telemetryConsentProvider);
    if (!_scheduledPrompt &&
        consent == null &&
        !kSkipTelemetryConsentPrompt &&
        kFirebaseAnalyticsEnabled &&
        Firebase.apps.isNotEmpty) {
      _scheduledPrompt = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Help improve Woleh'),
            content: const Text(
              'We use anonymous product analytics to see which features are used so we can improve the app. '
              'You can change this anytime in Profile → Privacy & analytics.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await ref
                      .read(telemetryConsentProvider.notifier)
                      .setProductAnalyticsAllowed(false);
                },
                child: const Text('No thanks'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await ref
                      .read(telemetryConsentProvider.notifier)
                      .setProductAnalyticsAllowed(true);
                },
                child: const Text('Allow'),
              ),
            ],
          ),
        );
      });
    }
    return widget.child;
  }
}
