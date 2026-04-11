package odm.clarity.woleh.subscription;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;

import odm.clarity.woleh.model.PaymentSession;
import odm.clarity.woleh.model.PaymentSessionStatus;
import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.model.Subscription;
import odm.clarity.woleh.model.SubscriptionStatus;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.payment.PaymentProviderAdapter;
import odm.clarity.woleh.payment.WebhookEvent;
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
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class WebhookIntegrationTest {

	private static final String WEBHOOK_URL = "/api/v1/webhooks/payment";
	private static final String ME_URL = "/api/v1/me";
	private static final String PHONE = "+233241888001";
	private static final String PROVIDER_REF = "stub_ref_001";

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired PlanRepository planRepository;
	@Autowired PaymentSessionRepository paymentSessionRepository;
	@Autowired SubscriptionRepository subscriptionRepository;
	@Autowired JwtService jwtService;

	@MockBean
	PaymentProviderAdapter paymentProviderAdapter;

	private User user;
	private Plan paidPlan;
	private String bearerToken;
	private PaymentSession pendingSession;

	@BeforeEach
	void setup() {
		subscriptionRepository.deleteAll();
		paymentSessionRepository.deleteAll();
		planRepository.deleteAll();
		userRepository.deleteAll();

		user = userRepository.save(new User(PHONE));
		bearerToken = "Bearer " + jwtService.createAccessToken(user.getId(), Instant.now());

		paidPlan = planRepository.save(new Plan(
				"woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				100, "GHS", 999999999, 999999999, true));

		// Create a pending payment session directly (bypasses checkout flow)
		pendingSession = paymentSessionRepository.save(new PaymentSession(
				user, paidPlan, "woleh_psess_test", "https://pay.stub/checkout", Instant.now().plus(30, ChronoUnit.MINUTES)));
		pendingSession.setProviderReference(PROVIDER_REF);
		paymentSessionRepository.save(pendingSession);

		// Default mock behaviour: valid signature, success event
		when(paymentProviderAdapter.verifyWebhookSignature(any(), any())).thenReturn(true);
		when(paymentProviderAdapter.parseWebhookEvent(any()))
				.thenReturn(new WebhookEvent("payment_success", PROVIDER_REF));
	}

	// ── success path ──────────────────────────────────────────────────────────

	@Test
	void webhook_successEvent_returns200() throws Exception {
		mockMvc.perform(post(WEBHOOK_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(successBody()))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"));
	}

	@Test
	void webhook_successEvent_markssessionCompleted() throws Exception {
		mockMvc.perform(post(WEBHOOK_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(successBody()));

		PaymentSession updated = paymentSessionRepository.findById(pendingSession.getId()).orElseThrow();
		assertThat(updated.getStatus()).isEqualTo(PaymentSessionStatus.COMPLETED);
	}

	@Test
	void webhook_successEvent_activatesSubscription() throws Exception {
		mockMvc.perform(post(WEBHOOK_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(successBody()));

		assertThat(subscriptionRepository.findTopByUser_IdAndStatusOrderByCurrentPeriodEndDesc(
				user.getId(), SubscriptionStatus.ACTIVE)).isPresent();
	}

	@Test
	void webhook_successEvent_getMe_returnsPaidTier() throws Exception {
		mockMvc.perform(post(WEBHOOK_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(successBody()));

		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.tier").value("paid"))
				.andExpect(jsonPath("$.data.permissions[?(@ == 'woleh.place.broadcast')]").exists())
				.andExpect(jsonPath("$.data.subscription.status").value("active"));
	}

	@Test
	void webhook_successEvent_cancelsLongRunningFreeSubscription() throws Exception {
		subscriptionRepository.deleteAll();
		Plan freePlan = planRepository.save(new Plan(
				SubscriptionPlanIds.FREE, "Free",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				0, "GHS", 999999999, 999999999, true));
		Instant freeHorizon = Instant.now().plus(36500, ChronoUnit.DAYS);
		Subscription freeSub = subscriptionRepository.save(new Subscription(
				user, freePlan, SubscriptionStatus.ACTIVE,
				Instant.now(), freeHorizon, freeHorizon.plus(7, ChronoUnit.DAYS)));

		mockMvc.perform(post(WEBHOOK_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(successBody()))
				.andExpect(status().isOk());

		assertThat(subscriptionRepository.findById(freeSub.getId()).orElseThrow().getStatus())
				.isEqualTo(SubscriptionStatus.CANCELLED);
		var active = subscriptionRepository.findTopByUser_IdAndStatusOrderByCurrentPeriodEndDesc(
				user.getId(), SubscriptionStatus.ACTIVE);
		assertThat(active).isPresent();
		assertThat(active.get().getPlan().getPlanId()).isEqualTo("woleh_paid_monthly");
	}

	// ── failure path ──────────────────────────────────────────────────────────

	@Test
	void webhook_failureEvent_marksSessionFailed() throws Exception {
		when(paymentProviderAdapter.parseWebhookEvent(any()))
				.thenReturn(new WebhookEvent("payment_failed", PROVIDER_REF));

		mockMvc.perform(post(WEBHOOK_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"type":"payment_failed","providerReference":"stub_ref_001"}
						"""))
				.andExpect(status().isOk());

		PaymentSession updated = paymentSessionRepository.findById(pendingSession.getId()).orElseThrow();
		assertThat(updated.getStatus()).isEqualTo(PaymentSessionStatus.FAILED);
		assertThat(subscriptionRepository.findTopByUser_IdAndStatusOrderByCurrentPeriodEndDesc(
				user.getId(), SubscriptionStatus.ACTIVE)).isEmpty();
	}

	// ── signature guard ───────────────────────────────────────────────────────

	@Test
	void webhook_invalidSignature_returns400() throws Exception {
		when(paymentProviderAdapter.verifyWebhookSignature(any(), any())).thenReturn(false);

		mockMvc.perform(post(WEBHOOK_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(successBody()))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("INVALID_SIGNATURE"));
	}

	// ── edge cases ────────────────────────────────────────────────────────────

	@Test
	void webhook_unknownProviderReference_returns200Gracefully() throws Exception {
		when(paymentProviderAdapter.parseWebhookEvent(any()))
				.thenReturn(new WebhookEvent("payment_success", "unknown_ref"));

		mockMvc.perform(post(WEBHOOK_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"type":"payment_success","providerReference":"unknown_ref"}
						"""))
				.andExpect(status().isOk());
	}

	@Test
	void webhook_duplicateSuccessEvent_idempotent() throws Exception {
		// First call activates subscription
		mockMvc.perform(post(WEBHOOK_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(successBody()));

		// Second call for the same session must not create a duplicate subscription
		mockMvc.perform(post(WEBHOOK_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(successBody()))
				.andExpect(status().isOk());

		assertThat(subscriptionRepository.findAll()).hasSize(1);
	}

	// ── helpers ──────────────────────────────────────────────────────────────

	private static String successBody() {
		return """
				{"type":"payment_success","providerReference":"stub_ref_001"}
				""";
	}
}
