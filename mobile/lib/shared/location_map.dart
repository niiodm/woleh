import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/location/location_fix.dart';
import 'map_location_pin.dart';
import 'osm_attribution.dart';

/// OpenStreetMap + markers for **self** (blue) and **peers** (orange).
///
/// While **following** the user, the camera moves with [self]. After the user
/// pans or zooms the map ([MapOptions.onPositionChanged] with `hasGesture`),
/// following stops until they tap **Recenter on my location**.
///
/// Phase 4 live map ([`MAP_LIVE_LOCATION_PLAN.md`](../../../docs/MAP_LIVE_LOCATION_PLAN.md) §4.4).
class LocationMap extends StatefulWidget {
  const LocationMap({
    super.key,
    required this.self,
    required this.peers,
    this.userFollowZoom = 15,
    this.alwaysShowRecenterButton = false,
  });

  final LocationFix? self;
  final List<MapLocationPin> peers;

  /// Zoom when following the user’s position.
  final double userFollowZoom;

  /// When true, the recenter FAB stays visible even while the camera is
  /// following the user (map-first home).
  final bool alwaysShowRecenterButton;

  static const _fallbackCenter = LatLng(5.6037, -0.187);

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  late final MapController _mapController;

  /// When true, [self] updates move the camera. Cleared after a user gesture.
  bool _followUser = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _moveToUserIfFollowing(),
    );
  }

  @override
  void didUpdateWidget(covariant LocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.self != null && oldWidget.self == null) {
      setState(() => _followUser = true);
    }
    if (widget.self != null &&
        _followUser &&
        (oldWidget.self == null ||
            oldWidget.self!.latitude != widget.self!.latitude ||
            oldWidget.self!.longitude != widget.self!.longitude)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _moveToUserIfFollowing(),
      );
    }
  }

  void _moveToUserIfFollowing() {
    if (!mounted || widget.self == null || !_followUser) return;
    _mapController.move(widget.self!.toLatLng(), widget.userFollowZoom);
  }

  void _recenterOnUser() {
    if (widget.self == null) return;
    setState(() => _followUser = true);
    _mapController.move(widget.self!.toLatLng(), widget.userFollowZoom);
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture || !mounted || widget.self == null) return;
    if (!_followUser) return;
    setState(() => _followUser = false);
  }

  LatLng _initialCenter() {
    if (widget.self != null) return widget.self!.toLatLng();
    if (widget.peers.isNotEmpty) return widget.peers.first.toLatLng();
    return LocationMap._fallbackCenter;
  }

  double _initialZoom() {
    if (widget.self != null || widget.peers.isNotEmpty) {
      return widget.userFollowZoom;
    }
    return 12;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _initialCenter(),
            initialZoom: _initialZoom(),
            onPositionChanged: _onPositionChanged,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'odm.clarity.woleh_mobile',
            ),
            SimpleAttributionWidget(
              alignment: Alignment.bottomLeft,
              source: const Text('OpenStreetMap contributors'),
              onTap: openOsmCopyrightPage,
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
        ),
        if (widget.self != null &&
            (widget.alwaysShowRecenterButton || !_followUser))
          Positioned(
            right: 12,
            bottom: 12,
            child: Material(
              elevation: 3,
              shadowColor: Colors.black26,
              shape: const CircleBorder(),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: IconButton(
                onPressed: _recenterOnUser,
                icon: Icon(
                  Icons.my_location,
                  color: Theme.of(context).colorScheme.primary,
                ),
                tooltip: 'Recenter on my location',
              ),
            ),
          ),
      ],
    );
  }
}
