import 'package:flutter_test/flutter_test.dart';
import 'package:odm_clarity_woleh_mobile/core/place_name_normalizer.dart';

void main() {
  // ── PLACE_NAMES.md §5 canonical test vectors ─────────────────────────────
  // These three vectors MUST pass on both client and server to guarantee that
  // the normalization pipelines produce identical results.

  group('PLACE_NAMES.md §5 canonical vectors', () {
    test('vector 1 — leading/trailing whitespace + case difference are equal', () {
      expect(normalizePlaceName('  Accra  '), equals(normalizePlaceName('accra')));
    });

    test('vector 2 — decomposed accent equals precomposed after NFC', () {
      // e + U+0301 (combining acute) is NFD for é; U+00E9 is NFC.
      const decomposed = 'e\u0301';
      const precomposed = '\u00e9';
      expect(normalizePlaceName(decomposed), equals(normalizePlaceName(precomposed)));
    });

    test('vector 3 — multiple internal spaces collapse to one', () {
      expect(normalizePlaceName('Main  St'), equals(normalizePlaceName('Main St')));
    });
  });

  // ── normalizePlaceName: edge cases ────────────────────────────────────────

  group('normalizePlaceName edge cases', () {
    test('empty string returns empty', () {
      expect(normalizePlaceName(''), isEmpty);
    });

    test('blank string (spaces only) returns empty', () {
      expect(normalizePlaceName('   '), isEmpty);
    });

    test('internal tab collapsed to single space', () {
      expect(normalizePlaceName('Accra\tCentral'), equals('accra central'));
    });

    test('mixed case is fully folded', () {
      expect(normalizePlaceName('CIRCLE'), equals('circle'));
      expect(normalizePlaceName('Kaneshie'), equals('kaneshie'));
    });

    test('exact output values match expected normal forms', () {
      expect(normalizePlaceName('  Accra  '), equals('accra'));
      expect(normalizePlaceName('Main  St'), equals('main st'));
    });

    test('mixed internal whitespace (tab + spaces) collapses correctly', () {
      expect(normalizePlaceName('Accra \t  Central'), equals('accra central'));
    });

    test('is idempotent — applying twice gives the same result', () {
      const input = '  Kaneshie  Market  ';
      final once = normalizePlaceName(input);
      expect(normalizePlaceName(once), equals(once));
    });

    test('Ghana-English place names normalize to expected forms', () {
      expect(normalizePlaceName('Madina'), equals('madina'));
      expect(normalizePlaceName('MADINA'), equals('madina'));
      expect(normalizePlaceName('  Madina '), equals('madina'));
      expect(normalizePlaceName('Lapaz'), equals('lapaz'));
      expect(normalizePlaceName('Legon'), equals('legon'));
    });
  });

  // ── validatePlaceName ─────────────────────────────────────────────────────

  group('validatePlaceName', () {
    group('valid inputs — returns null', () {
      test('typical place name is accepted', () {
        expect(validatePlaceName('Accra Central'), isNull);
      });

      test('exactly maxPlaceNameCodePoints characters is accepted', () {
        final maxName = 'a' * maxPlaceNameCodePoints;
        expect(validatePlaceName(maxName), isNull);
      });
    });

    group('invalid inputs — returns error string', () {
      test('null returns error', () {
        expect(validatePlaceName(null), isNotNull);
        expect(validatePlaceName(null), contains('empty'));
      });

      test('empty string returns error', () {
        expect(validatePlaceName(''), isNotNull);
        expect(validatePlaceName(''), contains('empty'));
      });

      test('blank string returns error', () {
        expect(validatePlaceName('   '), isNotNull);
        expect(validatePlaceName('   '), contains('empty'));
      });

      test('name exceeding $maxPlaceNameCodePoints code points returns error', () {
        final tooLong = 'a' * (maxPlaceNameCodePoints + 1);
        expect(validatePlaceName(tooLong), isNotNull);
        expect(validatePlaceName(tooLong), contains('$maxPlaceNameCodePoints'));
      });
    });
  });
}
