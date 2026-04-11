package odm.clarity.woleh.subscription;

/**
 * Canonical {@code plans.plan_id} values (Flyway {@code V4__seed_plans.sql}).
 */
public final class SubscriptionPlanIds {

	private SubscriptionPlanIds() {
	}

	public static final String FREE = "woleh_free";
	public static final String PAID_MONTHLY = "woleh_paid_monthly";
}
