import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/location_map.dart';
import '../../../shared/map_location_pin.dart';
import '../../me/presentation/me_notifier.dart';
import 'location_publish_notifier.dart';
import 'peer_locations_notifier.dart';

/// Live map: **self** from [locationPublishNotifierProvider], **peers** from
/// [peerLocationsNotifierProvider] ([`MAP_LIVE_LOCATION_PLAN.md`](../../../../../docs/MAP_LIVE_LOCATION_PLAN.md) §4.4).
class LiveMapScreen extends ConsumerWidget {
  const LiveMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(locationPublishNotifierProvider);
    final peerMap = ref.watch(peerLocationsNotifierProvider);
    final meAsync = ref.watch(meNotifierProvider);

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

    final sharingOn = meAsync.valueOrNull?.me.profile.locationSharingEnabled ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live map'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
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
                'Turn on location sharing in your profile settings to show your '
                'position and publish updates.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
              ),
            ),
          if (peerMap.isEmpty && sharingOn)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'No matched peers on the map yet — waiting for overlapping watch '
                'and broadcast names.',
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
                child: LocationMap(self: self, peers: peers),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
