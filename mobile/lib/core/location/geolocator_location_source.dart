import 'package:geolocator/geolocator.dart' as geo;

import 'location_fix.dart';
import 'location_source.dart';

/// Default [LocationSource] backed by the `geolocator` plugin.
class GeolocatorLocationSource implements LocationSource {
  @override
  Future<bool> isLocationServiceEnabled() => geo.Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationAuthorization> checkAuthorization() async {
    return _mapPermission(await geo.Geolocator.checkPermission());
  }

  @override
  Future<LocationAuthorization> requestWhenInUse() async {
    return _mapPermission(await geo.Geolocator.requestPermission());
  }

  @override
  Stream<LocationFix> watchPosition({
    LocationAccuracyTier accuracy = LocationAccuracyTier.high,
    double distanceFilterMeters = 0,
  }) {
    return geo.Geolocator.getPositionStream(
      locationSettings: geo.LocationSettings(
        accuracy: _geoAccuracy(accuracy),
        distanceFilter: distanceFilterMeters.round(),
      ),
    ).map(_fromPosition);
  }

  @override
  Future<LocationFix> getCurrentPosition({
    LocationAccuracyTier accuracy = LocationAccuracyTier.high,
  }) async {
    final position = await geo.Geolocator.getCurrentPosition(
      locationSettings: geo.LocationSettings(accuracy: _geoAccuracy(accuracy)),
    );
    return _fromPosition(position);
  }

  static LocationAuthorization _mapPermission(geo.LocationPermission p) {
    switch (p) {
      case geo.LocationPermission.denied:
        return LocationAuthorization.denied;
      case geo.LocationPermission.deniedForever:
        return LocationAuthorization.deniedForever;
      case geo.LocationPermission.whileInUse:
        return LocationAuthorization.whileInUse;
      case geo.LocationPermission.always:
        return LocationAuthorization.always;
      case geo.LocationPermission.unableToDetermine:
        return LocationAuthorization.denied;
    }
  }

  static geo.LocationAccuracy _geoAccuracy(LocationAccuracyTier tier) {
    switch (tier) {
      case LocationAccuracyTier.low:
        return geo.LocationAccuracy.low;
      case LocationAccuracyTier.balanced:
        return geo.LocationAccuracy.medium;
      case LocationAccuracyTier.high:
        return geo.LocationAccuracy.high;
      case LocationAccuracyTier.best:
        return geo.LocationAccuracy.best;
    }
  }

  static LocationFix _fromPosition(geo.Position p) {
    return LocationFix(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyMeters: p.accuracy,
      headingDegrees: p.heading,
      speedMetersPerSecond: p.speed,
      recordedAt: p.timestamp,
    );
  }
}
