import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/location/location_fix.dart';
import 'map_location_pin.dart';

/// OpenStreetMap + markers for **self** (blue) and **peers** (orange).
///
/// Keeps the camera centered on [self] when it updates ([`MapController.move`]).
///
/// Phase 4 live map ([`MAP_LIVE_LOCATION_PLAN.md`](../../../docs/MAP_LIVE_LOCATION_PLAN.md) §4.4).
class LocationMap extends StatefulWidget {
  const LocationMap({
    super.key,
    required this.self,
    required this.peers,
    this.userFollowZoom = 15,
  });

  final LocationFix? self;
  final List<MapLocationPin> peers;

  /// Zoom when following the user’s position.
  final double userFollowZoom;

  static const _fallbackCenter = LatLng(5.6037, -0.187);

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _moveToUserIfNeeded());
  }

  @override
  void didUpdateWidget(covariant LocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.self != null &&
        (oldWidget.self == null ||
            oldWidget.self!.latitude != widget.self!.latitude ||
            oldWidget.self!.longitude != widget.self!.longitude)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveToUserIfNeeded());
    }
  }

  void _moveToUserIfNeeded() {
    if (!mounted || widget.self == null) return;
    _mapController.move(widget.self!.toLatLng(), widget.userFollowZoom);
  }

  LatLng _initialCenter() {
    if (widget.self != null) return widget.self!.toLatLng();
    if (widget.peers.isNotEmpty) return widget.peers.first.toLatLng();
    return LocationMap._fallbackCenter;
  }

  double _initialZoom() {
    if (widget.self != null || widget.peers.isNotEmpty) return widget.userFollowZoom;
    return 12;
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialCenter(),
        initialZoom: _initialZoom(),
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
            for (final p in widget.peers)
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
            if (widget.self != null)
              Marker(
                point: widget.self!.toLatLng(),
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
}
