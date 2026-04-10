// ignore_for_file: avoid_classes_with_only_static_members

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Maximum number of Unicode code points a raw place name may contain.
/// Must match the server constant in {@code PlaceNameNormalizer.MAX_CODE_POINTS}.
const int maxPlaceNameCodePoints = 200;

/// Normalizes a raw place name for **equality comparison and matching**
/// (PLACE_NAMES.md §1 — v1 pipeline).
///
/// Pipeline applied in order:
/// 1. **Trim** — strip leading/trailing Unicode whitespace.
/// 2. **NFC** — compose to Unicode Normalization Form C via [unorm_dart].
///    Ensures that logically identical text from different keyboards (e.g.
///    precomposed vs decomposed accents) compares equal.
/// 3. **Case fold** — [String.toLowerCase] (sufficient for Latin-script
///    Ghana-English place names in v1; does not cover Turkish İ/ı or other
///    locale-specific case pairs — document and revisit if needed).
/// 4. **Collapse internal whitespace** — replace every maximal run of
///    whitespace with a single ASCII space; trim again.
///
/// Returns an empty string for blank-only or empty input.
/// The result is safe to use only for **equality checks and set operations**;
/// do not display it as a user-facing string.
String normalizePlaceName(String input) {
  var s = input.trim(); // step 1: trim
  s = unorm.nfc(s); // step 2: NFC
  s = s.toLowerCase(); // step 3: case fold
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim(); // step 4: collapse whitespace
  return s;
}

/// Validates a raw place name and returns an error message, or `null` if valid.
///
/// Rules (mirror of server `PlaceNameNormalizer.validatePlaceName`):
/// - Must be non-null and non-empty after trim.
/// - Must not exceed [maxPlaceNameCodePoints] Unicode code points.
///
/// Intended for use in form field validators:
/// ```dart
/// validator: (v) => validatePlaceName(v),
/// ```
String? validatePlaceName(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Place name must not be empty';
  }
  final codePointCount = raw.runes.length;
  if (codePointCount > maxPlaceNameCodePoints) {
    return 'Place name must not exceed $maxPlaceNameCodePoints Unicode code points';
  }
  return null;
}
