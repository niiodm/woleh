package odm.clarity.woleh.api.dto;

import jakarta.validation.constraints.NotNull;

/** Body for {@code PUT /api/v1/me/location-sharing}. */
public record LocationSharingRequest(@NotNull Boolean enabled) {
}
