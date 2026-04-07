// Phone number utilities for E.164 normalization and validation.
//
// UX is Ghana-focused (default country code +233) but the resulting value
// is a valid E.164 string accepted by any compliant server.

/// Normalizes a raw phone input toward E.164.
///
/// Rules (applied in order):
/// 1. Strip whitespace and common separators (spaces, dashes, parentheses).
/// 2. If the result starts with `0` it is a local Ghana number: replace the
///    leading `0` with `+233`.
/// 3. If the result has no leading `+`, prepend `+233`.
/// 4. Return the result; the caller should validate with [isValidE164].
String normalizePhone(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'[\s\-().]+'), '');
  if (s.startsWith('0')) return '+233${s.substring(1)}';
  if (!s.startsWith('+')) return '+233$s';
  return s;
}

/// Returns true when [phone] is a structurally valid E.164 string.
///
/// Criteria: `+` followed by 9–14 digits (ITU-T E.164 allows up to 15 digits
/// total including the country code, so the subscriber part is 9–14 after the
/// `+`).
bool isValidE164(String phone) =>
    RegExp(r'^\+[1-9]\d{8,13}$').hasMatch(phone);
