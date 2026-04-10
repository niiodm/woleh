import 'location_fix.dart';

/// OS-level authorization for device location (mirrors `geolocator` semantics).
enum LocationAuthorization {
  denied,
  deniedForever,
  whileInUse,
  always,
}

/// Requested accuracy for reads and streams (mapped to `geolocator` settings).
enum LocationAccuracyTier {
  low,
  balanced,
  high,
  best,
}

/// Foreground device location — [`ARCHITECTURE.md`](../../../../docs/ARCHITECTURE.md) §4.1,
/// [`MAP_LIVE_LOCATION_PLAN.md`](../../../../docs/MAP_LIVE_LOCATION_PLAN.md) §4.1.
///
/// Map widgets stay in `lib/features/*/presentation/`; this stays in `core/`.
abstract class LocationSource {
  Future<bool> isLocationServiceEnabled();

  Future<LocationAuthorization> checkAuthorization();

  /// May show the system permission dialog.
  Future<LocationAuthorization> requestWhenInUse();

  Stream<LocationFix> watchPosition({
    LocationAccuracyTier accuracy = LocationAccuracyTier.high,
    double distanceFilterMeters = 0,
  });

  Future<LocationFix> getCurrentPosition({
    LocationAccuracyTier accuracy = LocationAccuracyTier.high,
  });
}
