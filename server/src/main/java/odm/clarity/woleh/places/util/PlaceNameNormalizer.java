package odm.clarity.woleh.places.util;

import java.text.Normalizer;
import java.util.Locale;

import odm.clarity.woleh.common.error.PlaceNameValidationException;

import org.springframework.stereotype.Component;

/**
 * Normalizes place names for equality checks and matching.
 *
 * Pipeline (applied in order per PLACE_NAMES.md §1):
 *   1. Trim          — strip leading/trailing Unicode whitespace
 *   2. NFC           — Unicode Normalization Form C (composed accents)
 *   3. Case fold     — toLowerCase(Locale.ROOT); language-neutral for v1 Ghana-English
 *   4. Collapse      — maximal internal whitespace runs → single ASCII space; re-trim
 *
 * The result is used ONLY for comparison and deduplication.
 * The user-entered display string is stored separately.
 */
@Component
public class PlaceNameNormalizer {

	/** Maximum allowed Unicode code points (scalar values) per place name. */
	public static final int MAX_CODE_POINTS = 200;

	/**
	 * Normalize {@code input} through the four-step pipeline.
	 * Returns an empty string for null or blank input (callers should reject
	 * empty normalized names via {@link #validatePlaceName}).
	 */
	public String normalize(String input) {
		if (input == null) {
			return "";
		}

		// Step 1: trim (strip is Unicode-aware in Java 11+)
		String s = input.strip();

		// Step 2: NFC — composed form ensures e.g. decomposed accents equal precomposed ones
		s = Normalizer.normalize(s, Normalizer.Form.NFC);

		// Step 3: case fold (Locale.ROOT = language-neutral)
		s = s.toLowerCase(Locale.ROOT);

		// Step 4: collapse internal whitespace; re-strip in case platform adds edge spaces
		s = s.replaceAll("\\s+", " ").strip();

		return s;
	}

	/**
	 * Validate a raw (user-entered) place name before storing.
	 * Throws {@link PlaceNameValidationException} if the name is invalid.
	 *
	 * Rules:
	 * <ul>
	 *   <li>Non-empty after trim</li>
	 *   <li>At most {@value #MAX_CODE_POINTS} Unicode code points (scalar values)</li>
	 * </ul>
	 */
	public void validatePlaceName(String raw) {
		if (raw == null || raw.strip().isEmpty()) {
			throw new PlaceNameValidationException("Place name must not be empty");
		}
		int codePoints = raw.codePointCount(0, raw.length());
		if (codePoints > MAX_CODE_POINTS) {
			throw new PlaceNameValidationException(
					"Place name must not exceed " + MAX_CODE_POINTS + " Unicode code points");
		}
	}
}
