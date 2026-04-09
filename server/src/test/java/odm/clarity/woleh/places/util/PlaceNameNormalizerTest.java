package odm.clarity.woleh.places.util;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import odm.clarity.woleh.common.error.PlaceNameValidationException;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class PlaceNameNormalizerTest {

	private PlaceNameNormalizer normalizer;

	@BeforeEach
	void setUp() {
		normalizer = new PlaceNameNormalizer();
	}

	// ── PLACE_NAMES.md §5 canonical test vectors ───────────────────────────

	/** Vector 1: leading/trailing whitespace + case difference → equal. */
	@Test
	void vector1_leadingTrailingSpacesAndCaseAreEquivalent() {
		assertThat(normalizer.normalize("  Accra  "))
				.isEqualTo(normalizer.normalize("accra"));
	}

	/** Vector 2: decomposed accent (e + U+0301) equals precomposed (U+00E9) after NFC. */
	@Test
	void vector2_decomposedAndPrecomposedAccentAreEqual() {
		String decomposed = "e\u0301"; // e + combining acute accent
		String precomposed = "\u00E9"; // é precomposed
		assertThat(normalizer.normalize(decomposed))
				.isEqualTo(normalizer.normalize(precomposed));
	}

	/** Vector 3: multiple internal spaces collapse to one. */
	@Test
	void vector3_multipleInternalSpacesCollapsedToOne() {
		assertThat(normalizer.normalize("Main  St"))
				.isEqualTo(normalizer.normalize("Main St"));
	}

	// ── normalize: edge cases ─────────────────────────────────────────────

	@Test
	void normalize_emptyStringReturnsEmpty() {
		assertThat(normalizer.normalize("")).isEmpty();
	}

	@Test
	void normalize_nullReturnsEmpty() {
		assertThat(normalizer.normalize(null)).isEmpty();
	}

	@Test
	void normalize_blankStringReturnsEmpty() {
		assertThat(normalizer.normalize("   ")).isEmpty();
	}

	@Test
	void normalize_internalTabCollapsedToSpace() {
		assertThat(normalizer.normalize("Accra\tCentral"))
				.isEqualTo("accra central");
	}

	@Test
	void normalize_mixedCaseFolded() {
		assertThat(normalizer.normalize("CIRCLE")).isEqualTo("circle");
		assertThat(normalizer.normalize("Kaneshie")).isEqualTo("kaneshie");
	}

	@Test
	void normalize_exactOutputValues() {
		assertThat(normalizer.normalize("  Accra  ")).isEqualTo("accra");
		assertThat(normalizer.normalize("Main  St")).isEqualTo("main st");
	}

	@Test
	void normalize_isIdempotent() {
		String input = "  Kaneshie  Market  ";
		String once = normalizer.normalize(input);
		assertThat(normalizer.normalize(once)).isEqualTo(once);
	}

	@Test
	void normalize_mixedInternalWhitespace() {
		// Tab + multiple spaces between words
		assertThat(normalizer.normalize("Accra \t  Central"))
				.isEqualTo("accra central");
	}

	// ── validatePlaceName: valid inputs ──────────────────────────────────

	@Test
	void validatePlaceName_typicalNameDoesNotThrow() {
		normalizer.validatePlaceName("Accra Central");
	}

	@Test
	void validatePlaceName_exactlyMaxCodePointsAccepted() {
		String maxName = "a".repeat(PlaceNameNormalizer.MAX_CODE_POINTS);
		normalizer.validatePlaceName(maxName); // must not throw
	}

	// ── validatePlaceName: invalid inputs ────────────────────────────────

	@Test
	void validatePlaceName_nullThrows() {
		assertThatThrownBy(() -> normalizer.validatePlaceName(null))
				.isInstanceOf(PlaceNameValidationException.class)
				.hasMessageContaining("empty");
	}

	@Test
	void validatePlaceName_emptyStringThrows() {
		assertThatThrownBy(() -> normalizer.validatePlaceName(""))
				.isInstanceOf(PlaceNameValidationException.class)
				.hasMessageContaining("empty");
	}

	@Test
	void validatePlaceName_blankStringThrows() {
		assertThatThrownBy(() -> normalizer.validatePlaceName("   "))
				.isInstanceOf(PlaceNameValidationException.class)
				.hasMessageContaining("empty");
	}

	@Test
	void validatePlaceName_201CodePointsThrows() {
		String tooLong = "a".repeat(PlaceNameNormalizer.MAX_CODE_POINTS + 1);
		assertThatThrownBy(() -> normalizer.validatePlaceName(tooLong))
				.isInstanceOf(PlaceNameValidationException.class)
				.hasMessageContaining("200");
	}
}
