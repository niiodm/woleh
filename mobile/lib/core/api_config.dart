/// API host base URL (scheme + host + port), **without** `/api/v1`.
///
/// Set at build time, e.g.
/// `flutter run --dart-define=API_BASE_URL=http://<lan-ip>:8080`.
/// Defaults to the Android emulator alias for the host machine.
const apiHostBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);
