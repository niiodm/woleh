package odm.clarity.woleh.places.dto;

import java.util.List;

import jakarta.validation.constraints.NotNull;

/**
 * Request body for {@code PUT /api/v1/me/saved-place-lists/{id}} — full replacement of title and names.
 */
public record SavedPlaceListUpdateRequest(String title, @NotNull List<String> names) {
}
