import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Map marker input for [LocationMap] — keeps `shared/` free of feature DTOs.
@immutable
class MapLocationPin {
  const MapLocationPin({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.label,
  });

  final String id;
  final double latitude;
  final double longitude;

  /// Short label (e.g. truncated user id) for tooltips.
  final String? label;

  LatLng toLatLng() => LatLng(latitude, longitude);
}
