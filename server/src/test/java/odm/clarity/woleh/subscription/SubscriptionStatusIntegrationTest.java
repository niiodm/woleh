package odm.clarity.woleh.subscription;

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
class SubscriptionStatusIntegrationTest {

	private static final String STATUS_URL = "/api/v1/subscription/status";
	private static final String PHONE = "+233241777001";

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

	// ── auth guard ────────────────────────────────────────────────────────────

	@Test
	void status_withoutAuth_returns401() throws Exception {
		mockMvc.perform(get(STATUS_URL))
				.andExpect(status().isUnauthorized());
	}

	// ── free tier ─────────────────────────────────────────────────────────────

	@Test
	void status_freeUser_returnsFreeTierShape() throws Exception {
		mockMvc.perform(get(STATUS_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"))
				.andExpect(jsonPath("$.data.tier").value("free"))
				.andExpect(jsonPath("$.data.permissions").isArray())
				.andExpect(jsonPath("$.data.permissions[?(@ == 'woleh.account.profile')]").exists())
				.andExpect(jsonPath("$.data.limits.placeWatchMax").value(5))
				.andExpect(jsonPath("$.data.limits.placeBroadcastMax").value(0))
				.andExpect(jsonPath("$.data.subscription.status").value("none"))
				.andExpect(jsonPath("$.data.subscription.inGracePeriod").value(false));
	}

	// ── paid tier ─────────────────────────────────────────────────────────────

	@Test
	void status_paidUser_returnsPaidTierShape() throws Exception {
		Plan plan = planRepository.save(new Plan(
				"woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				100, "GHS", 999999999, 999999999, true));
		Instant periodEnd = Instant.now().plus(30, ChronoUnit.DAYS);
		subscriptionRepository.save(new Subscription(
				user, plan, SubscriptionStatus.ACTIVE,
				Instant.now(), periodEnd, periodEnd.plus(7, ChronoUnit.DAYS)));

		mockMvc.perform(get(STATUS_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.tier").value("paid"))
				.andExpect(jsonPath("$.data.permissions[?(@ == 'woleh.place.broadcast')]").exists())
				.andExpect(jsonPath("$.data.limits.placeWatchMax").value(999999999))
				.andExpect(jsonPath("$.data.limits.placeBroadcastMax").value(999999999))
				.andExpect(jsonPath("$.data.subscription.status").value("active"))
				.andExpect(jsonPath("$.data.subscription.currentPeriodEnd").isString())
				.andExpect(jsonPath("$.data.subscription.inGracePeriod").value(false));
	}

	@Test
	void status_gracePeriodUser_showsGraceFlag() throws Exception {
		Plan plan = planRepository.save(new Plan(
				"woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				100, "GHS", 999999999, 999999999, true));
		Instant periodEnd = Instant.now().minus(2, ChronoUnit.DAYS);
		subscriptionRepository.save(new Subscription(
				user, plan, SubscriptionStatus.ACTIVE,
				periodEnd.minus(30, ChronoUnit.DAYS), periodEnd,
				Instant.now().plus(5, ChronoUnit.DAYS)));

		mockMvc.perform(get(STATUS_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.tier").value("paid"))
				.andExpect(jsonPath("$.data.subscription.status").value("active"))
				.andExpect(jsonPath("$.data.subscription.inGracePeriod").value(true));
	}
}
