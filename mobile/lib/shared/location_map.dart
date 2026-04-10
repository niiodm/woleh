import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/location/location_fix.dart';
import 'map_location_pin.dart';

/// OpenStreetMap + markers for **self** (blue) and **peers** (orange).
///
/// Phase 4 live map ([`MAP_LIVE_LOCATION_PLAN.md`](../../../docs/MAP_LIVE_LOCATION_PLAN.md) §4.4).
class LocationMap extends StatelessWidget {
  const LocationMap({
    super.key,
    required this.self,
    required this.peers,
  });

  final LocationFix? self;
  final List<MapLocationPin> peers;

  static const _fallbackCenter = LatLng(5.6037, -0.187);

  @override
  Widget build(BuildContext context) {
    final center = _center();
    final zoom = _zoomFor(center);

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'odm.clarity.woleh_mobile',
        ),
        MarkerLayer(
          markers: [
            for (final p in peers)
              Marker(
                point: p.toLatLng(),
                width: 36,
                height: 36,
                child: Tooltip(
                  message: p.label ?? 'Peer ${p.id}',
                  child: Icon(
                    Icons.place,
                    color: Colors.deepOrange.shade700,
                    size: 36,
                  ),
                ),
              ),
            if (self != null)
              Marker(
                point: self!.toLatLng(),
                width: 40,
                height: 40,
                child: Tooltip(
                  message: 'You',
                  child: Icon(
                    Icons.navigation,
                    color: Colors.blue.shade700,
                    size: 40,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  LatLng _center() {
    if (self != null) return self!.toLatLng();
    if (peers.isNotEmpty) return peers.first.toLatLng();
    return _fallbackCenter;
  }

  double _zoomFor(LatLng _) {
    if (self != null || peers.isNotEmpty) return 14;
    return 12;
  }
}
