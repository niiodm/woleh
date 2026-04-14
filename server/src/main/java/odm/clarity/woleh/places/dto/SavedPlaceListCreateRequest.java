package odm.clarity.woleh.places.dto;

import java.util.List;

import jakarta.validation.constraints.NotNull;

/**
 * Request body for {@code POST /api/v1/me/saved-place-lists}.
 */
public record SavedPlaceListCreateRequest(String title, @NotNull List<String> names) {
}
