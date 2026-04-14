package odm.clarity.woleh.places.dto;

import java.time.Instant;

/** One row in {@code GET /api/v1/me/saved-place-lists}. */
public record SavedPlaceListSummaryResponse(
		long id,
		String title,
		int placeCount,
		String shareToken,
		Instant updatedAt) {
}
