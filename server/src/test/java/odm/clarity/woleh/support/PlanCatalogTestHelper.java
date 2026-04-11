package odm.clarity.woleh.support;

import java.util.List;

import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.repository.PlanRepository;
import odm.clarity.woleh.subscription.SubscriptionPlanIds;

/**
 * Integration tests use an empty schema (no Flyway); signup needs {@link SubscriptionPlanIds#FREE}.
 */
public final class PlanCatalogTestHelper {

	private PlanCatalogTestHelper() {
	}

	public static void ensureDefaultPlans(PlanRepository planRepository) {
		if (planRepository.findByPlanId(SubscriptionPlanIds.FREE).isEmpty()) {
			planRepository.save(new Plan(
					SubscriptionPlanIds.FREE, "Free",
					List.of("woleh.account.profile", "woleh.plans.read",
							"woleh.place.watch", "woleh.place.broadcast"),
					0, "GHS", 999999999, 999999999, true));
		}
		if (planRepository.findByPlanId(SubscriptionPlanIds.PAID_MONTHLY).isEmpty()) {
			planRepository.save(new Plan(
					SubscriptionPlanIds.PAID_MONTHLY, "Woleh Pro",
					List.of("woleh.account.profile", "woleh.plans.read",
							"woleh.place.watch", "woleh.place.broadcast"),
					100, "GHS", 999999999, 999999999, true));
		}
	}
}
