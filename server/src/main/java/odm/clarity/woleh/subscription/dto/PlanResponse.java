package odm.clarity.woleh.subscription.dto;

import java.util.List;

/**
 * API response shape for a single plan entry in {@code GET /api/v1/subscription/plans}
 * (API_CONTRACT.md §6.5).
 */
public record PlanResponse(
		String planId,
		String displayName,
		List<String> permissionsGranted,
		Limits limits,
		Price price) {

	public record Limits(int placeWatchMax, int placeBroadcastMax) {
	}

	public record Price(int amountMinor, String currency) {
	}
}
