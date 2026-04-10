package odm.clarity.woleh.api.dto;

import java.util.List;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Response body for {@code GET /api/v1/me}.
 * Per API_CONTRACT.md §6.3 — profile + Phase-0 free-tier entitlements.
 */
public record MeResponse(
		Profile profile,
		List<String> permissions,
		String tier,
		Limits limits,
		Subscription subscription) {

	public record Profile(
			String userId,
			String phoneE164,
			@JsonInclude(JsonInclude.Include.ALWAYS) String displayName,
			boolean locationSharingEnabled) {
	}

	public record Limits(int placeWatchMax, int placeBroadcastMax) {
	}

	public record Subscription(
			String status,
			@JsonInclude(JsonInclude.Include.ALWAYS) String currentPeriodEnd,
			boolean inGracePeriod) {
	}
}
