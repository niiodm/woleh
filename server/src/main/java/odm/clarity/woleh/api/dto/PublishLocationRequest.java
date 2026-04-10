package odm.clarity.woleh.api.dto;

import java.time.Instant;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.PositiveOrZero;

/**
 * Body for {@code POST /api/v1/me/location} (MAP_LIVE_LOCATION_PLAN §3.2).
 */
public record PublishLocationRequest(
		@NotNull @DecimalMin("-90.0") @DecimalMax("90.0") Double latitude,
		@NotNull @DecimalMin("-180.0") @DecimalMax("180.0") Double longitude,
		@Positive Double accuracyMeters,
		@DecimalMin("0.0") @DecimalMax("360.0") Double heading,
		@PositiveOrZero Double speed,
		Instant recordedAt) {
}
