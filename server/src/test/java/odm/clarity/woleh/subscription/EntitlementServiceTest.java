package odm.clarity.woleh.subscription;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;

import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.model.Subscription;
import odm.clarity.woleh.model.SubscriptionStatus;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.SubscriptionRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class EntitlementServiceTest {

	private static final Long USER_ID = 1L;
	private static final List<String> PAID_PERMISSIONS = List.of(
			"woleh.account.profile", "woleh.plans.read",
			"woleh.place.watch", "woleh.place.broadcast");

	private SubscriptionRepository subscriptionRepository;
	private EntitlementService service;

	@BeforeEach
	void setUp() {
		subscriptionRepository = mock(SubscriptionRepository.class);
		service = new EntitlementService(subscriptionRepository);
	}

	@Test
	void freeTierWhenNoActiveSubscription() {
		when(subscriptionRepository.findTopByUser_IdAndStatusOrderByCurrentPeriodEndDesc(
				eq(USER_ID), any())).thenReturn(Optional.empty());

		Entitlements result = service.computeEntitlements(USER_ID);

		assertThat(result.tier()).isEqualTo("free");
		assertThat(result.permissions()).containsExactlyElementsOf(EntitlementService.FREE_PERMISSIONS);
		assertThat(result.placeWatchMax()).isEqualTo(EntitlementService.FREE_WATCH_MAX);
		assertThat(result.placeBroadcastMax()).isEqualTo(EntitlementService.FREE_BROADCAST_MAX);
		assertThat(result.savedPlaceListMax()).isEqualTo(EntitlementService.FREE_SAVED_PLACE_LIST_MAX);
		assertThat(result.subscriptionStatus()).isEqualTo("none");
		assertThat(result.currentPeriodEnd()).isNull();
		assertThat(result.inGracePeriod()).isFalse();
	}

	@Test
	void freeTierWhenActiveFreeCatalogSubscription() {
		Instant periodEnd = Instant.now().plus(100, ChronoUnit.DAYS);
		Instant graceEnd = periodEnd.plus(7, ChronoUnit.DAYS);
		Plan plan = new Plan(
				SubscriptionPlanIds.FREE, "Free",
				PAID_PERMISSIONS, 0, "GHS", 999999999, 999999999, 100, true);
		User user = new User("+233241000001");
		Subscription sub = new Subscription(user, plan, SubscriptionStatus.ACTIVE,
				Instant.now(), periodEnd, graceEnd);

		when(subscriptionRepository.findTopByUser_IdAndStatusOrderByCurrentPeriodEndDesc(
				eq(USER_ID), any())).thenReturn(Optional.of(sub));

		Entitlements result = service.computeEntitlements(USER_ID);

		assertThat(result.tier()).isEqualTo("free");
		assertThat(result.permissions()).containsExactlyElementsOf(PAID_PERMISSIONS);
		assertThat(result.placeWatchMax()).isEqualTo(999999999);
		assertThat(result.placeBroadcastMax()).isEqualTo(999999999);
		assertThat(result.savedPlaceListMax()).isEqualTo(100);
		assertThat(result.subscriptionStatus()).isEqualTo("active");
		assertThat(result.inGracePeriod()).isFalse();
	}

	@Test
	void paidTierWhenActiveSubscriptionWithinPeriod() {
		Instant periodEnd = Instant.now().plus(29, ChronoUnit.DAYS);
		Instant graceEnd = periodEnd.plus(7, ChronoUnit.DAYS);
		Subscription sub = buildSubscription(periodEnd, graceEnd);

		when(subscriptionRepository.findTopByUser_IdAndStatusOrderByCurrentPeriodEndDesc(
				eq(USER_ID), any())).thenReturn(Optional.of(sub));

		Entitlements result = service.computeEntitlements(USER_ID);

		assertThat(result.tier()).isEqualTo("paid");
		assertThat(result.permissions()).containsExactlyElementsOf(PAID_PERMISSIONS);
		assertThat(result.placeWatchMax()).isEqualTo(50);
		assertThat(result.placeBroadcastMax()).isEqualTo(50);
		assertThat(result.savedPlaceListMax()).isEqualTo(20);
		assertThat(result.subscriptionStatus()).isEqualTo("active");
		assertThat(result.currentPeriodEnd()).isEqualTo(periodEnd.toString());
		assertThat(result.inGracePeriod()).isFalse();
	}

	@Test
	void paidTierWithGraceFlagWhenBetweenPeriodEndAndGraceEnd() {
		// currentPeriodEnd is 2 days in the past; gracePeriodEnd is 5 days in the future.
		Instant periodEnd = Instant.now().minus(2, ChronoUnit.DAYS);
		Instant graceEnd = Instant.now().plus(5, ChronoUnit.DAYS);
		Subscription sub = buildSubscription(periodEnd, graceEnd);

		when(subscriptionRepository.findTopByUser_IdAndStatusOrderByCurrentPeriodEndDesc(
				eq(USER_ID), any())).thenReturn(Optional.of(sub));

		Entitlements result = service.computeEntitlements(USER_ID);

		assertThat(result.tier()).isEqualTo("paid");
		assertThat(result.permissions()).containsExactlyElementsOf(PAID_PERMISSIONS);
		assertThat(result.subscriptionStatus()).isEqualTo("active");
		assertThat(result.currentPeriodEnd()).isEqualTo(periodEnd.toString());
		assertThat(result.inGracePeriod()).isTrue();
	}

	@Test
	void freeTierWhenSubscriptionPastGracePeriod() {
		// Both currentPeriodEnd and gracePeriodEnd are in the past.
		Instant periodEnd = Instant.now().minus(10, ChronoUnit.DAYS);
		Instant graceEnd = Instant.now().minus(3, ChronoUnit.DAYS);
		Subscription sub = buildSubscription(periodEnd, graceEnd);

		when(subscriptionRepository.findTopByUser_IdAndStatusOrderByCurrentPeriodEndDesc(
				eq(USER_ID), any())).thenReturn(Optional.of(sub));

		Entitlements result = service.computeEntitlements(USER_ID);

		assertThat(result.tier()).isEqualTo("free");
		assertThat(result.permissions()).containsExactlyElementsOf(EntitlementService.FREE_PERMISSIONS);
		assertThat(result.subscriptionStatus()).isEqualTo("none");
		assertThat(result.inGracePeriod()).isFalse();
	}

	// ── helpers ──────────────────────────────────────────────────────────────

	private static Subscription buildSubscription(Instant periodEnd, Instant graceEnd) {
		Plan plan = new Plan(
				"woleh_paid_monthly", "Woleh Pro",
				PAID_PERMISSIONS, 100, "GHS", 50, 50, 20, true);
		User user = new User("+233241000001");
		return new Subscription(user, plan, SubscriptionStatus.ACTIVE,
				periodEnd.minus(30, ChronoUnit.DAYS), periodEnd, graceEnd);
	}
}
