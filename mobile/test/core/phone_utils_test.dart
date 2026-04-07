import 'package:flutter_test/flutter_test.dart';
import 'package:odm_clarity_woleh_mobile/core/phone_utils.dart';

void main() {
  group('normalizePhone', () {
    group('local Ghana format (leading 0)', () {
      test('10-digit local number', () {
        expect(normalizePhone('0241234567'), '+233241234567');
      });

      test('strips spaces then normalizes', () {
        expect(normalizePhone(' 024 123 4567 '), '+233241234567');
      });

      test('strips dashes then normalizes', () {
        expect(normalizePhone('024-123-4567'), '+233241234567');
      });
    });

    group('number without country code or leading 0', () {
      test('9-digit subscriber number', () {
        expect(normalizePhone('241234567'), '+233241234567');
      });
    });

    group('already E.164', () {
      test('Ghana number', () {
        expect(normalizePhone('+233241234567'), '+233241234567');
      });

      test('non-Ghana E.164 left unchanged', () {
        expect(normalizePhone('+14155552671'), '+14155552671');
      });

      test('spaces inside E.164 are stripped', () {
        expect(normalizePhone('+233 24 123 4567'), '+233241234567');
      });
    });
  });

  group('isValidE164', () {
    group('valid numbers', () {
      test('standard Ghana mobile', () {
        expect(isValidE164('+233241234567'), isTrue);
      });

      test('US number', () {
        expect(isValidE164('+14155552671'), isTrue);
      });

      test('minimum length (10 chars total: + 1 country + 8 subscriber)', () {
        expect(isValidE164('+123456789'), isTrue);
      });

      test('maximum length (15 chars total)', () {
        expect(isValidE164('+' + '1' * 14), isTrue);
      });
    });

    group('invalid numbers', () {
      test('missing leading +', () {
        expect(isValidE164('233241234567'), isFalse);
      });

      test('local format with leading 0', () {
        expect(isValidE164('0241234567'), isFalse);
      });

      test('too short (fewer than 9 digits after +)', () {
        expect(isValidE164('+12345678'), isFalse);
      });

      test('too long (more than 14 digits after +)', () {
        expect(isValidE164('+' + '1' * 15), isFalse);
      });

      test('non-digit characters after +', () {
        expect(isValidE164('+233abc4567'), isFalse);
      });

      test('country code starting with 0', () {
        expect(isValidE164('+023241234567'), isFalse);
      });

      test('empty string', () {
        expect(isValidE164(''), isFalse);
      });

      test('just a +', () {
        expect(isValidE164('+'), isFalse);
      });
    });

    group('normalizePhone then isValidE164 round-trip', () {
      test('local Ghana number round-trips to valid E.164', () {
        expect(isValidE164(normalizePhone('0241234567')), isTrue);
      });

      test('already E.164 remains valid after normalize', () {
        expect(isValidE164(normalizePhone('+233241234567')), isTrue);
      });
    });
  });
}
