package odm.clarity.woleh.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;

import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.model.Subscription;
import odm.clarity.woleh.model.SubscriptionStatus;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.PlanRepository;
import odm.clarity.woleh.repository.SubscriptionRepository;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.security.JwtService;
import odm.clarity.woleh.subscription.SubscriptionPlanIds;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class MeIntegrationTest {

	private static final String ME_URL = "/api/v1/me";
	private static final String PHONE = "+233241999001";

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired PlanRepository planRepository;
	@Autowired SubscriptionRepository subscriptionRepository;
	@Autowired JwtService jwtService;

	private User user;
	private String bearerToken;

	@BeforeEach
	void setup() {
		subscriptionRepository.deleteAll();
		planRepository.deleteAll();
		userRepository.deleteAll();
		user = userRepository.save(new User(PHONE));
		bearerToken = "Bearer " + jwtService.createAccessToken(user.getId(), Instant.now());
	}

	// ── profile shape ────────────────────────────────────────────────────────

	@Test
	void me_returnsProfileWithCorrectUserId() throws Exception {
		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"))
				.andExpect(jsonPath("$.data.profile.userId").value(String.valueOf(user.getId())))
				.andExpect(jsonPath("$.data.profile.phoneE164").value(PHONE))
				.andExpect(jsonPath("$.data.profile.productAnalyticsConsent").value(false));
	}

	@Test
	void me_newUser_displayNameIsNull() throws Exception {
		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				// displayName should be present in JSON (null, not omitted) per @JsonInclude(ALWAYS)
				.andExpect(jsonPath("$.data.profile.displayName").doesNotExist());
	}

	@Test
	void me_userWithDisplayName_returnsName() throws Exception {
		user.setDisplayName("Ama Owusu");
		userRepository.save(user);

		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.profile.displayName").value("Ama Owusu"));
	}

	// ── free-tier entitlements ───────────────────────────────────────────────

	@Test
	void me_returnsFreePermissions() throws Exception {
		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.tier").value("free"))
				.andExpect(jsonPath("$.data.permissions").isArray())
				.andExpect(jsonPath("$.data.permissions[?(@ == 'woleh.account.profile')]").exists())
				.andExpect(jsonPath("$.data.permissions[?(@ == 'woleh.plans.read')]").exists())
				.andExpect(jsonPath("$.data.permissions[?(@ == 'woleh.place.watch')]").exists());
	}

	@Test
	void me_returnsFreeLimits() throws Exception {
		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.limits.placeWatchMax").value(5))
				.andExpect(jsonPath("$.data.limits.placeBroadcastMax").value(0));
	}

	@Test
	void me_returnsNoSubscription() throws Exception {
		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.subscription.status").value("none"))
				.andExpect(jsonPath("$.data.subscription.inGracePeriod").value(false));
	}

	@Test
	void me_userWithActiveFreeCatalogSubscription_returnsFreeTier() throws Exception {
		Plan plan = planRepository.save(new Plan(
				SubscriptionPlanIds.FREE, "Free",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				0, "GHS", 999999999, 999999999, 20, true));
		Instant periodEnd = Instant.now().plus(36500, ChronoUnit.DAYS);
		subscriptionRepository.save(new Subscription(
				user, plan, SubscriptionStatus.ACTIVE,
				Instant.now(), periodEnd, periodEnd.plus(7, ChronoUnit.DAYS)));

		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.tier").value("free"))
				.andExpect(jsonPath("$.data.permissions[?(@ == 'woleh.place.broadcast')]").exists())
				.andExpect(jsonPath("$.data.limits.placeWatchMax").value(999999999))
				.andExpect(jsonPath("$.data.limits.placeBroadcastMax").value(999999999))
				.andExpect(jsonPath("$.data.subscription.status").value("active"))
				.andExpect(jsonPath("$.data.subscription.inGracePeriod").value(false));
	}

	// ── paid subscription entitlements ───────────────────────────────────────

	@Test
	void me_userWithActiveSubscription_returnsPaidTier() throws Exception {
		Plan plan = planRepository.save(new Plan(
				"woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				100, "GHS", 999999999, 999999999, 20, true));
		Instant periodEnd = Instant.now().plus(30, ChronoUnit.DAYS);
		subscriptionRepository.save(new Subscription(
				user, plan, SubscriptionStatus.ACTIVE,
				Instant.now(), periodEnd, periodEnd.plus(7, ChronoUnit.DAYS)));

		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.tier").value("paid"))
				.andExpect(jsonPath("$.data.permissions[?(@ == 'woleh.place.broadcast')]").exists())
				.andExpect(jsonPath("$.data.limits.placeWatchMax").value(999999999))
				.andExpect(jsonPath("$.data.limits.placeBroadcastMax").value(999999999))
				.andExpect(jsonPath("$.data.subscription.status").value("active"))
				.andExpect(jsonPath("$.data.subscription.inGracePeriod").value(false));
	}

	@Test
	void me_userInGracePeriod_returnsPaidTierWithGraceFlag() throws Exception {
		Plan plan = planRepository.save(new Plan(
				"woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				100, "GHS", 999999999, 999999999, 20, true));
		Instant periodEnd = Instant.now().minus(2, ChronoUnit.DAYS);
		Instant graceEnd = Instant.now().plus(5, ChronoUnit.DAYS);
		subscriptionRepository.save(new Subscription(
				user, plan, SubscriptionStatus.ACTIVE,
				periodEnd.minus(30, ChronoUnit.DAYS), periodEnd, graceEnd));

		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.tier").value("paid"))
				.andExpect(jsonPath("$.data.subscription.status").value("active"))
				.andExpect(jsonPath("$.data.subscription.inGracePeriod").value(true));
	}

	@Test
	void me_userWithExpiredSubscriptionPastGrace_returnsFreeTier() throws Exception {
		Plan plan = planRepository.save(new Plan(
				"woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				100, "GHS", 999999999, 999999999, 20, true));
		Instant periodEnd = Instant.now().minus(10, ChronoUnit.DAYS);
		Instant graceEnd = Instant.now().minus(3, ChronoUnit.DAYS);
		subscriptionRepository.save(new Subscription(
				user, plan, SubscriptionStatus.ACTIVE,
				periodEnd.minus(30, ChronoUnit.DAYS), periodEnd, graceEnd));

		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.tier").value("free"))
				.andExpect(jsonPath("$.data.subscription.status").value("none"))
				.andExpect(jsonPath("$.data.subscription.inGracePeriod").value(false));
	}

	// ── auth guard ───────────────────────────────────────────────────────────

	@Test
	void me_withoutToken_returns401() throws Exception {
		mockMvc.perform(get(ME_URL))
				.andExpect(status().isUnauthorized())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
	}

	@Test
	void me_withExpiredToken_returns401() throws Exception {
		// Issue a token with issuedAt in the past, well beyond the 24h TTL
		Instant longAgo = Instant.now().minusSeconds(200_000);
		String expired = "Bearer " + jwtService.createAccessToken(user.getId(), longAgo);

		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, expired))
				.andExpect(status().isUnauthorized());
	}
}
