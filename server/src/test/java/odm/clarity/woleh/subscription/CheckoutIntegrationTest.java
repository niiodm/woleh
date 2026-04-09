package odm.clarity.woleh.subscription;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;

import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.PaymentSessionRepository;
import odm.clarity.woleh.repository.PlanRepository;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.security.JwtService;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class CheckoutIntegrationTest {

	private static final String CHECKOUT_URL = "/api/v1/subscription/checkout";
	private static final String PHONE = "+233241999099";

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired PlanRepository planRepository;
	@Autowired PaymentSessionRepository paymentSessionRepository;
	@Autowired JwtService jwtService;

	private User user;
	private String bearerToken;
	private Plan paidPlan;

	@BeforeEach
	void setup() {
		paymentSessionRepository.deleteAll();
		planRepository.deleteAll();
		userRepository.deleteAll();

		user = userRepository.save(new User(PHONE));
		bearerToken = "Bearer " + jwtService.createAccessToken(user.getId(), Instant.now());

		planRepository.save(new Plan(
				"woleh_free", "Free",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				0, "GHS", 999999999, 999999999, true));
		paidPlan = planRepository.save(new Plan(
				"woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				100, "GHS", 999999999, 999999999, true));
	}

	// ── auth guard ────────────────────────────────────────────────────────────

	@Test
	void checkout_withoutAuth_returns401() throws Exception {
		mockMvc.perform(post(CHECKOUT_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"planId":"woleh_paid_monthly"}
						"""))
				.andExpect(status().isUnauthorized());
	}

	// ── validation errors ─────────────────────────────────────────────────────

	@Test
	void checkout_missingPlanId_returns400() throws Exception {
		mockMvc.perform(post(CHECKOUT_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("{}"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"));
	}

	@Test
	void checkout_unknownPlan_returns400() throws Exception {
		mockMvc.perform(post(CHECKOUT_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"planId":"does_not_exist"}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.data").doesNotExist());
	}

	@Test
	void checkout_freePlan_returns400() throws Exception {
		mockMvc.perform(post(CHECKOUT_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"planId":"woleh_free"}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"));
	}

	// ── happy path ────────────────────────────────────────────────────────────

	@Test
	void checkout_validPaidPlan_returns200WithCheckoutUrl() throws Exception {
		mockMvc.perform(post(CHECKOUT_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"planId":"woleh_paid_monthly"}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"))
				.andExpect(jsonPath("$.data.checkoutUrl").value(
						org.hamcrest.Matchers.containsString("/api/v1/dev/checkout-stub")))
				.andExpect(jsonPath("$.data.sessionId").value(
						org.hamcrest.Matchers.startsWith("woleh_psess_")))
				.andExpect(jsonPath("$.data.expiresAt").isString());
	}

	@Test
	void checkout_duplicateRequest_returnsSameSession() throws Exception {
		String body = """
				{"planId":"woleh_paid_monthly"}
				""";

		String first = mockMvc.perform(post(CHECKOUT_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body))
				.andExpect(status().isOk())
				.andReturn().getResponse().getContentAsString();

		String second = mockMvc.perform(post(CHECKOUT_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body))
				.andExpect(status().isOk())
				.andReturn().getResponse().getContentAsString();

		String firstSessionId = com.jayway.jsonpath.JsonPath.read(first, "$.data.sessionId");
		String secondSessionId = com.jayway.jsonpath.JsonPath.read(second, "$.data.sessionId");
		assertThat(secondSessionId).isEqualTo(firstSessionId);
	}
}
