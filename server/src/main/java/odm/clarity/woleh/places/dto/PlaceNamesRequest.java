package odm.clarity.woleh.places.dto;

import java.util.List;

import jakarta.validation.constraints.NotNull;

/**
 * Request body for PUT place-name list endpoints.
 * {@code names} is the full replacement list (empty list clears the current list).
 * Individual name validation (length, non-empty after trim) is done in the service layer.
 */
public record PlaceNamesRequest(@NotNull List<String> names) {
}
