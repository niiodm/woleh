import 'package:latlong2/latlong.dart';

/// A single device position reading for map display and server publish (Phase 4).
///
/// Kept free of `geolocator` types so features and tests depend on this layer only.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.headingDegrees,
    this.speedMetersPerSecond,
    this.recordedAt,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? headingDegrees;
  final double? speedMetersPerSecond;
  final DateTime? recordedAt;

  /// For `flutter_map` / OSM markers ([`latlong2`](https://pub.dev/packages/latlong2)).
  LatLng toLatLng() => LatLng(latitude, longitude);
}
