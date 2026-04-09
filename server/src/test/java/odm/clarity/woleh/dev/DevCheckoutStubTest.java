package odm.clarity.woleh.dev;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;

import odm.clarity.woleh.model.PaymentSession;
import odm.clarity.woleh.model.PaymentSessionStatus;
import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.model.Subscription;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.PaymentSessionRepository;
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
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;

import com.jayway.jsonpath.JsonPath;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class DevCheckoutStubTest {

	private static final String STUB_URL = "/api/v1/dev/checkout-stub";
	private static final String PHONE = "+233241888201";
	private static final String SESSION_ID = "woleh_psess_teststubsessionabc123";
	private static final String PROVIDER_REF = SESSION_ID; // stub sets providerRef = sessionId

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired PlanRepository planRepository;
	@Autowired PaymentSessionRepository paymentSessionRepository;
	@Autowired SubscriptionRepository subscriptionRepository;
	@Autowired JwtService jwtService;

	private User user;
	private Plan plan;
	private String bearerToken;

	@BeforeEach
	void setup() {
		subscriptionRepository.deleteAll();
		paymentSessionRepository.deleteAll();
		planRepository.deleteAll();
		userRepository.deleteAll();

		user = userRepository.save(new User(PHONE));
		plan = planRepository.save(new Plan(
				"woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				100, "GHS", 999999999, 999999999, true));
		bearerToken = "Bearer " + jwtService.createAccessToken(user.getId(), Instant.now());
	}

	// ── helpers ────────────────────────────────────────────────────────────────

	private PaymentSession savedPendingSession() {
		PaymentSession ps = new PaymentSession(
				user, plan, SESSION_ID,
				"http://localhost/api/v1/dev/checkout-stub?sessionId=" + SESSION_ID,
				Instant.now().plus(30, ChronoUnit.MINUTES));
		ps.setProviderReference(PROVIDER_REF);
		return paymentSessionRepository.save(ps);
	}

	// ── HTML stub page ─────────────────────────────────────────────────────────

	@Test
	void stub_withoutResult_rendersHtmlWithBothLinks() throws Exception {
		savedPendingSession();

		String body = mockMvc.perform(get(STUB_URL).param("sessionId", SESSION_ID))
				.andExpect(status().isOk())
				.andReturn()
				.getResponse()
				.getContentAsString();

		assertThat(body).contains("result=success");
		assertThat(body).contains("result=failure");
		assertThat(body).contains(SESSION_ID);
	}

	// ── success path ───────────────────────────────────────────────────────────

	@Test
	void stub_success_redirectsToDeepLink() throws Exception {
		savedPendingSession();

		mockMvc.perform(get(STUB_URL).param("sessionId", SESSION_ID).param("result", "success"))
				.andExpect(status().isFound())
				.andExpect(header().string(HttpHeaders.LOCATION,
						"woleh://subscription/result?status=success&sessionId=" + SESSION_ID));
	}

	@Test
	void stub_success_activatesSubscription() throws Exception {
		savedPendingSession();

		mockMvc.perform(get(STUB_URL).param("sessionId", SESSION_ID).param("result", "success"))
				.andExpect(status().isFound());

		PaymentSession updated = paymentSessionRepository.findBySessionId(SESSION_ID).orElseThrow();
		assertThat(updated.getStatus()).isEqualTo(PaymentSessionStatus.COMPLETED);

		List<Subscription> subs = subscriptionRepository.findAll();
		assertThat(subs).hasSize(1);
		assertThat(subs.get(0).getPlan().getPlanId()).isEqualTo("woleh_paid_monthly");
	}

	// ── failure path ───────────────────────────────────────────────────────────

	@Test
	void stub_failure_redirectsToDeepLinkAndMarksSessionFailed() throws Exception {
		savedPendingSession();

		mockMvc.perform(get(STUB_URL).param("sessionId", SESSION_ID).param("result", "failure"))
				.andExpect(status().isFound())
				.andExpect(header().string(HttpHeaders.LOCATION,
						"woleh://subscription/result?status=failure&sessionId=" + SESSION_ID));

		PaymentSession updated = paymentSessionRepository.findBySessionId(SESSION_ID).orElseThrow();
		assertThat(updated.getStatus()).isEqualTo(PaymentSessionStatus.FAILED);
		assertThat(subscriptionRepository.findAll()).isEmpty();
	}

	// ── error cases ────────────────────────────────────────────────────────────

	@Test
	void stub_unknownSessionId_returns400() throws Exception {
		mockMvc.perform(get(STUB_URL).param("sessionId", "unknown-session-xyz"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("NOT_FOUND"));
	}

	@Test
	void stub_invalidResult_returns400() throws Exception {
		savedPendingSession();

		mockMvc.perform(get(STUB_URL).param("sessionId", SESSION_ID).param("result", "bogus"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("BAD_REQUEST"));
	}

	// ── full end-to-end loop ───────────────────────────────────────────────────

	@Test
	void fullLoop_checkoutThenStubSuccess_getMeReturnsPaidTier() throws Exception {
		// Step 1: Initiate checkout
		MvcResult checkoutResult = mockMvc.perform(post("/api/v1/subscription/checkout")
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"planId\":\"woleh_paid_monthly\"}"))
				.andExpect(status().isOk())
				.andReturn();

		String sessionId = JsonPath.read(
				checkoutResult.getResponse().getContentAsString(), "$.data.sessionId");

		// Step 2: Simulate success via stub
		mockMvc.perform(get(STUB_URL).param("sessionId", sessionId).param("result", "success"))
				.andExpect(status().isFound())
				.andExpect(header().string(HttpHeaders.LOCATION,
						org.hamcrest.Matchers.containsString("status=success")));

		// Step 3: GET /me should now reflect paid tier
		mockMvc.perform(get("/api/v1/me").header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.tier").value("paid"))
				.andExpect(jsonPath("$.data.permissions[?(@ == 'woleh.place.broadcast')]").exists());
	}
}
