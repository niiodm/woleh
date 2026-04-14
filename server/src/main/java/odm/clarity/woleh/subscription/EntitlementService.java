package odm.clarity.woleh.subscription;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.model.Subscription;
import odm.clarity.woleh.model.SubscriptionStatus;
import odm.clarity.woleh.repository.SubscriptionRepository;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Computes a user's effective entitlements (permissions, tier, limits, subscription
 * status) from the active subscription in the database.
 *
 * <p>Grace period: if now is after {@code currentPeriodEnd} but before {@code gracePeriodEnd}
 * (7 days — PRD §13.6) the subscription's plan permissions are kept and
 * {@code inGracePeriod} is set to {@code true}.
 *
 * <p>Falls back to free-tier defaults (PRD §13.1) when no active subscription exists
 * or when the grace window has also closed.
 *
 * <p>Tier {@code "free"} is returned both for that fallback and for an active subscription
 * on plan {@link SubscriptionPlanIds#FREE}; paid catalog plans use tier {@code "paid"}.
 */
@Service
@Transactional(readOnly = true)
public class EntitlementService {

	// Free-tier defaults (PRD §13.1). These are the baseline every account receives
	// without a paid subscription; broadcast is not included.
	static final List<String> FREE_PERMISSIONS = List.of(
			"woleh.account.profile",
			"woleh.plans.read",
			"woleh.place.watch");
	static final int FREE_WATCH_MAX = 5;
	static final int FREE_BROADCAST_MAX = 0;
	/** Max saved place list templates when the user has no active subscription (PRD free tier). */
	static final int FREE_SAVED_PLACE_LIST_MAX = 10;

	private final SubscriptionRepository subscriptionRepository;

	public EntitlementService(SubscriptionRepository subscriptionRepository) {
		this.subscriptionRepository = subscriptionRepository;
	}

	/**
	 * Returns the effective entitlements for the given user at the current moment.
	 *
	 * <p>The subscription's {@link Plan} association is lazy-loaded within this
	 * transaction; callers do not need a transaction of their own.
	 */
	public Entitlements computeEntitlements(Long userId) {
		Optional<Subscription> found = subscriptionRepository
				.findTopByUser_IdAndStatusOrderByCurrentPeriodEndDesc(userId, SubscriptionStatus.ACTIVE);

		if (found.isEmpty()) {
			return freeTier();
		}

		Subscription sub = found.get();
		Instant now = Instant.now();

		if (now.isAfter(sub.getGracePeriodEnd())) {
			return freeTier();
		}

		Plan plan = sub.getPlan();
		boolean inGrace = now.isAfter(sub.getCurrentPeriodEnd());
		String tier = SubscriptionPlanIds.FREE.equals(plan.getPlanId()) ? "free" : "paid";

		return new Entitlements(
				plan.getPermissionsGranted(),
				tier,
				plan.getPlaceWatchMax(),
				plan.getPlaceBroadcastMax(),
				plan.getSavedPlaceListMax(),
				"active",
				sub.getCurrentPeriodEnd().toString(),
				inGrace);
	}

	private static Entitlements freeTier() {
		return new Entitlements(FREE_PERMISSIONS, "free", FREE_WATCH_MAX, FREE_BROADCAST_MAX,
				FREE_SAVED_PLACE_LIST_MAX,
				"none", null, false);
	}
}
