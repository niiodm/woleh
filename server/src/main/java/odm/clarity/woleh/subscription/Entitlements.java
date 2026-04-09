package odm.clarity.woleh.subscription;

import java.util.List;

/**
 * Computed entitlements for a user: permissions, tier, place-list limits, and
 * subscription status.  Returned by {@link EntitlementService} and consumed by
 * controllers to build API responses without duplicating business rules.
 */
public record Entitlements(
		List<String> permissions,
		String tier,
		int placeWatchMax,
		int placeBroadcastMax,
		String subscriptionStatus,
		String currentPeriodEnd,
		boolean inGracePeriod) {
}
