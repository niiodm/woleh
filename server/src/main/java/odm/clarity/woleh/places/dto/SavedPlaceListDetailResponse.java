package odm.clarity.woleh.places.dto;

import java.time.Instant;
import java.util.List;

/** Response for {@code GET /api/v1/me/saved-place-lists/{id}}. */
public record SavedPlaceListDetailResponse(
		long id,
		String title,
		List<String> names,
		String shareToken,
		Instant createdAt,
		Instant updatedAt) {
}
