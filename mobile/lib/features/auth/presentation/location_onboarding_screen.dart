import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics_provider.dart';
import '../../../core/location/location_source.dart';
import '../../../core/location/location_source_provider.dart';
import '../../../core/location_onboarding.dart';
import '../../../core/shared_preferences_provider.dart';

/// Explains why device location is needed, then triggers the OS permission prompt.
///
/// Shown once for users who can open the live map (watch or broadcast permission).
class LocationOnboardingScreen extends ConsumerStatefulWidget {
  const LocationOnboardingScreen({super.key});

  @override
  ConsumerState<LocationOnboardingScreen> createState() =>
      _LocationOnboardingScreenState();
}

class _LocationOnboardingScreenState extends ConsumerState<LocationOnboardingScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeSkipIfAlreadyGranted());
    });
  }

  Future<void> _maybeSkipIfAlreadyGranted() async {
    final src = ref.read(locationSourceProvider);
    final authz = await src.checkAuthorization();
    if (!mounted) return;
    if (authz == LocationAuthorization.whileInUse ||
        authz == LocationAuthorization.always) {
      await _markCompleteAndGo();
    }
  }

  Future<void> _markCompleteAndGo() async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(kLocationOnboardingCompletedKey, true);
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _onAllowLocation() async {
    unawaited(
      ref.read(wolehAnalyticsProvider).logButtonTapped(
            'allow_location_access',
            screenName: '/auth/location-intro',
          ),
    );
    setState(() => _busy = true);
    try {
      final src = ref.read(locationSourceProvider);
      final servicesOn = await src.isLocationServiceEnabled();
      if (!mounted) return;
      if (!servicesOn) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Turn on Location Services for this device, then tap Allow again.',
            ),
          ),
        );
        return;
      }
      await src.requestWhenInUse();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    unawaited(
      ref.read(wolehAnalyticsProvider).logEvent('location_onboarding_completed', {
        'action': 'allow_tap',
      }),
    );
    await _markCompleteAndGo();
  }

  Future<void> _onNotNow() async {
    unawaited(
      ref.read(wolehAnalyticsProvider).logButtonTapped(
            'location_intro_not_now',
            screenName: '/auth/location-intro',
          ),
    );
    unawaited(
      ref.read(wolehAnalyticsProvider).logEvent('location_onboarding_completed', {
        'action': 'not_now',
      }),
    );
    await _markCompleteAndGo();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.map_outlined, size: 64, color: colors.primary),
              const SizedBox(height: 24),
              Text(
                'Location is required',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Woleh shows you on the live map and matches you with buses and '
                'passengers. The next step is a one-time system prompt — please '
                'allow location access while you use the app.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'You can also turn on “Share location with matches” later in '
                'Profile if it was off.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : () => unawaited(_onAllowLocation()),
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Allow location access'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy ? null : () => unawaited(_onNotNow()),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
