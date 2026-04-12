import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/location/location_fix.dart';
import '../../../core/location/location_source.dart';
import '../../../core/location/location_source_provider.dart';
import '../../../shared/location_map.dart';
import '../../../shared/map_location_pin.dart';
import '../../me/presentation/me_notifier.dart';
import 'location_publish_notifier.dart';
import 'peer_locations_notifier.dart';

/// Location permission + map layer shared by [LiveMapScreen] and the map-first home route.
///
/// Set [forMapHome] for a full-bleed map with a persistent recenter control.
class LiveMapStack extends ConsumerStatefulWidget {
  const LiveMapStack({super.key, this.forMapHome = false});

  /// When true, the map fills the stack (no outer [Column]); hints sit in an
  /// overlay. When false, uses the padded, rounded layout from the old live map screen.
  final bool forMapHome;

  @override
  ConsumerState<LiveMapStack> createState() => _LiveMapStackState();
}

enum _LiveMapGate { checking, granted, servicesDisabled, denied, deniedForever }

class _LiveMapStackState extends ConsumerState<LiveMapStack> {
  _LiveMapGate _gate = _LiveMapGate.checking;
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
      setState(() => _gate = _LiveMapGate.servicesDisabled);
      return;
    }

    final authz = await src.requestWhenInUse();
    if (!mounted) return;

    switch (authz) {
      case LocationAuthorization.whileInUse:
      case LocationAuthorization.always:
        setState(() => _gate = _LiveMapGate.granted);
        await _bootstrapUserPositionIfNeeded();
      case LocationAuthorization.denied:
        setState(() => _gate = _LiveMapGate.denied);
      case LocationAuthorization.deniedForever:
        setState(() => _gate = _LiveMapGate.deniedForever);
    }
  }

  Future<void> _bootstrapUserPositionIfNeeded() async {
    final published = ref.read(locationPublishNotifierProvider);
    if (published != null || !mounted) return;

    try {
      final fix = await ref.read(locationSourceProvider).getCurrentPosition();
      if (mounted) setState(() => _bootstrapSelf = fix);
    } catch (_) {}
  }

  Future<void> _retryPermission() async {
    setState(() {
      _gate = _LiveMapGate.checking;
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

    return switch (_gate) {
      _LiveMapGate.checking => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_searching,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Requesting location access…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      _LiveMapGate.servicesDisabled => _PermissionPlaceholder(
        icon: Icons.location_off_outlined,
        title: 'Location services are off',
        detail:
            'Turn on location for this device so the map can center on you.',
        primaryLabel: 'Open location settings',
        onPrimary: () => Geolocator.openLocationSettings(),
        secondaryLabel: 'Try again',
        onSecondary: _retryPermission,
      ),
      _LiveMapGate.denied => _PermissionPlaceholder(
        icon: Icons.map_outlined,
        title: 'Location permission needed',
        detail: 'Woleh needs your location to show where you are on the map.',
        primaryLabel: 'Ask again',
        onPrimary: _retryPermission,
      ),
      _LiveMapGate.deniedForever => _PermissionPlaceholder(
        icon: Icons.settings_outlined,
        title: 'Location blocked',
        detail:
            'Enable location for Woleh in system settings to use the live map.',
        primaryLabel: 'Open app settings',
        onPrimary: () => Geolocator.openAppSettings(),
        secondaryLabel: 'Try again',
        onSecondary: _retryPermission,
      ),
      _LiveMapGate.granted =>
        widget.forMapHome
            ? _MapHomeGrantedBody(
                selfForMap: selfForMap,
                peers: peers,
                sharingOn: sharingOn,
                peerMapEmpty: peerMap.isEmpty,
              )
            : _EmbeddedGrantedBody(
                selfForMap: selfForMap,
                peers: peers,
                sharingOn: sharingOn,
                peerMapEmpty: peerMap.isEmpty,
              ),
    };
  }
}

class _EmbeddedGrantedBody extends StatelessWidget {
  const _EmbeddedGrantedBody({
    required this.selfForMap,
    required this.peers,
    required this.sharingOn,
    required this.peerMapEmpty,
  });

  final LocationFix? selfForMap;
  final List<MapLocationPin> peers;
  final bool sharingOn;
  final bool peerMapEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Peer positions appear when place names match a user who is '
            'sharing their location. Turn on sharing in Profile to publish '
            'your own position to matched peers.',
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
        if (peerMapEmpty && sharingOn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'No matched peers on the map yet — check overlapping watch '
              'and broadcast place names, or wait for their next location update.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    );
  }
}

class _MapHomeGrantedBody extends StatelessWidget {
  const _MapHomeGrantedBody({
    required this.selfForMap,
    required this.peers,
    required this.sharingOn,
    required this.peerMapEmpty,
  });

  final LocationFix? selfForMap;
  final List<MapLocationPin> peers;
  final bool sharingOn;
  final bool peerMapEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hintStyle = Theme.of(context).textTheme.bodySmall;

    String? overlayText;
    if (!sharingOn) {
      overlayText =
          'Turn on location sharing in Profile so matched peers can see you.';
    } else if (peerMapEmpty) {
      overlayText =
          'No matched peers yet — add place names via search to find buses or passengers.';
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        LocationMap(
          self: selfForMap,
          peers: peers,
          alwaysShowRecenterButton: true,
        ),
        if (overlayText != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: 88,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  overlayText,
                  style: hintStyle?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
      ],
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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
