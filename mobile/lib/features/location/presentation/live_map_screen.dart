import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/location/location_fix.dart';
import '../../../core/location/location_source.dart';
import '../../../core/location/location_source_provider.dart';
import '../../../shared/location_map.dart';
import '../../../shared/map_location_pin.dart';
import '../../me/presentation/me_notifier.dart';
import 'location_publish_notifier.dart';
import 'peer_locations_notifier.dart';

/// Live map: **self** from [locationPublishNotifierProvider], **peers** from
/// [peerLocationsNotifierProvider] ([`MAP_LIVE_LOCATION_PLAN.md`](../../../../../docs/MAP_LIVE_LOCATION_PLAN.md) §4.4).
///
/// Requests **when-in-use** location permission before showing the map, then
/// centers on the user (published fix or a one-shot [LocationSource.getCurrentPosition]).
class LiveMapScreen extends ConsumerStatefulWidget {
  const LiveMapScreen({super.key});

  @override
  ConsumerState<LiveMapScreen> createState() => _LiveMapScreenState();
}

enum _LocationGate {
  checking,
  granted,
  servicesDisabled,
  denied,
  deniedForever,
}

class _LiveMapScreenState extends ConsumerState<LiveMapScreen> {
  _LocationGate _gate = _LocationGate.checking;
  LocationFix? _bootstrapSelf;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runLocationGate());
  }

  Future<void> _runLocationGate() async {
    final src = ref.read(locationSourceProvider);

    final servicesOn = await src.isLocationServiceEnabled();
    if (!mounted) return;
    if (!servicesOn) {
      setState(() => _gate = _LocationGate.servicesDisabled);
      return;
    }

    final authz = await src.requestWhenInUse();
    if (!mounted) return;

    switch (authz) {
      case LocationAuthorization.whileInUse:
      case LocationAuthorization.always:
        setState(() => _gate = _LocationGate.granted);
        await _bootstrapUserPositionIfNeeded();
      case LocationAuthorization.denied:
        setState(() => _gate = _LocationGate.denied);
      case LocationAuthorization.deniedForever:
        setState(() => _gate = _LocationGate.deniedForever);
    }
  }

  /// One fix for map center when [locationPublishNotifierProvider] has nothing yet (e.g. sharing off).
  Future<void> _bootstrapUserPositionIfNeeded() async {
    final published = ref.read(locationPublishNotifierProvider);
    if (published != null || !mounted) return;

    try {
      final fix =
          await ref.read(locationSourceProvider).getCurrentPosition();
      if (mounted) setState(() => _bootstrapSelf = fix);
    } catch (_) {
      // Map still shows fallback center; user may enable sharing for stream.
    }
  }

  Future<void> _retryPermission() async {
    setState(() {
      _gate = _LocationGate.checking;
      _bootstrapSelf = null;
    });
    await _runLocationGate();
  }

  @override
  Widget build(BuildContext context) {
    final publishedSelf = ref.watch(locationPublishNotifierProvider);
    final peerMap = ref.watch(peerLocationsNotifierProvider);
    final meAsync = ref.watch(meNotifierProvider);

    final selfForMap = publishedSelf ?? _bootstrapSelf;

    final peers = peerMap.values
        .map(
          (p) => MapLocationPin(
            id: p.userId,
            latitude: p.latitude,
            longitude: p.longitude,
            label: 'Peer (${p.userId})',
          ),
        )
        .toList();

    final sharingOn =
        meAsync.valueOrNull?.me.profile.locationSharingEnabled ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live map'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: switch (_gate) {
        _LocationGate.checking => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Requesting location access…'),
              ],
            ),
          ),
        _LocationGate.servicesDisabled => _PermissionPlaceholder(
          icon: Icons.location_off_outlined,
          title: 'Location services are off',
          detail:
              'Turn on location for this device so the map can center on you.',
          primaryLabel: 'Open location settings',
          onPrimary: () => Geolocator.openLocationSettings(),
          secondaryLabel: 'Try again',
          onSecondary: _retryPermission,
        ),
        _LocationGate.denied => _PermissionPlaceholder(
          icon: Icons.map_outlined,
          title: 'Location permission needed',
          detail:
              'Woleh needs your location to show where you are on the map.',
          primaryLabel: 'Ask again',
          onPrimary: _retryPermission,
        ),
        _LocationGate.deniedForever => _PermissionPlaceholder(
          icon: Icons.settings_outlined,
          title: 'Location blocked',
          detail:
              'Enable location for Woleh in system settings to use the live map.',
          primaryLabel: 'Open app settings',
          onPrimary: () => Geolocator.openAppSettings(),
          secondaryLabel: 'Try again',
          onSecondary: _retryPermission,
        ),
        _LocationGate.granted => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Peer positions appear only when you share location and place '
                  'names match another user who is also sharing.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              if (!sharingOn)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Turn on location sharing in your profile settings to show '
                    'your position to matched peers and keep publishing updates.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                  ),
                ),
              if (peerMap.isEmpty && sharingOn)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'No matched peers on the map yet — waiting for overlapping '
                    'watch and broadcast names.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LocationMap(self: selfForMap, peers: peers),
                  ),
                ),
              ),
            ],
          ),
      },
    );
  }
}

class _PermissionPlaceholder extends StatelessWidget {
  const _PermissionPlaceholder({
    required this.icon,
    required this.title,
    required this.detail,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colors.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onPrimary,
              child: Text(primaryLabel),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
