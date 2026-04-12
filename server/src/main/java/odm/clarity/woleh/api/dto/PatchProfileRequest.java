package odm.clarity.woleh.api.dto;

import jakarta.validation.constraints.Null;
import jakarta.validation.constraints.Size;

/**
 * Body for {@code PATCH /api/v1/me/profile} (API_CONTRACT.md §6.4).
 *
 * <p>Mutable fields: {@code displayName}, {@code productAnalyticsConsent}. Sending
 * {@code phoneE164} is an explicit error: the {@code @Null} constraint turns it into a
 * 400 validation failure rather than silently ignoring the field.
 */
public record PatchProfileRequest(
		@Size(min = 1, max = 255, message = "must be between 1 and 255 characters")
		String displayName,

		@Null(message = "phoneE164 is immutable and cannot be changed")
		String phoneE164,

		Boolean productAnalyticsConsent) {
}
