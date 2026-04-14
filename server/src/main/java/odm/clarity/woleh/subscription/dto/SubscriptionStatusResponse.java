package odm.clarity.woleh.subscription.dto;

import java.util.List;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Response body for {@code GET /api/v1/subscription/status} (API_CONTRACT.md §5).
 * Mirrors the entitlements block returned by {@code GET /me} so the client has a
 * dedicated endpoint to refresh subscription state without re-fetching the full profile.
 */
public record SubscriptionStatusResponse(
		List<String> permissions,
		String tier,
		Limits limits,
		Subscription subscription) {

	public record Limits(int placeWatchMax, int placeBroadcastMax, int savedPlaceListMax) {
	}

	public record Subscription(
			String status,
			@JsonInclude(JsonInclude.Include.ALWAYS) String currentPeriodEnd,
			boolean inGracePeriod) {
	}
}
