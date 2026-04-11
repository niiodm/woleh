package odm.clarity.woleh.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;

import odm.clarity.woleh.model.OtpChallenge;
import odm.clarity.woleh.model.SubscriptionStatus;
import odm.clarity.woleh.repository.OtpChallengeRepository;
import odm.clarity.woleh.repository.PlanRepository;
import odm.clarity.woleh.repository.SubscriptionRepository;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.subscription.SubscriptionPlanIds;
import odm.clarity.woleh.support.PlanCatalogTestHelper;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class VerifyOtpIntegrationTest {

	private static final String VERIFY_URL = "/api/v1/auth/verify-otp";
	private static final String PHONE = "+447911500100";
	private static final String OTP = "654321";

	@Autowired MockMvc mockMvc;
	@Autowired OtpChallengeRepository otpChallengeRepository;
	@Autowired UserRepository userRepository;
	@Autowired PlanRepository planRepository;
	@Autowired SubscriptionRepository subscriptionRepository;
	@Autowired PasswordEncoder passwordEncoder;

	@BeforeEach
	void seed() {
		otpChallengeRepository.deleteAll();
		userRepository.deleteAll();
		PlanCatalogTestHelper.ensureDefaultPlans(planRepository);
		createChallenge(PHONE, OTP, Instant.now().plusSeconds(300));
	}

	// ── happy paths ──────────────────────────────────────────────────────────

	@Test
	void verifyOtp_newUser_returnsSignupFlowAndJwt() throws Exception {
		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, OTP)))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"))
				.andExpect(jsonPath("$.data.flow").value("signup"))
				.andExpect(jsonPath("$.data.tokenType").value("Bearer"))
				.andExpect(jsonPath("$.data.accessToken").isNotEmpty())
				.andExpect(jsonPath("$.data.expiresInSeconds").isNumber())
				.andExpect(jsonPath("$.data.userId").isNotEmpty())
				.andExpect(jsonPath("$.data.refreshToken").isNotEmpty());
	}

	@Test
	void verifyOtp_existingUser_returnsLoginFlow() throws Exception {
		// Pre-create the user so the phone is already registered
		userRepository.save(new odm.clarity.woleh.model.User(PHONE));

		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, OTP)))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.flow").value("login"));
	}

	@Test
	void verifyOtp_successMarksOtpConsumed() throws Exception {
		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, OTP)))
				.andExpect(status().isOk());

		// consumed=true means the challenge should not appear in unconsumed list
		var pending = otpChallengeRepository
				.findByPhoneE164AndConsumedOrderByCreatedAtDesc(PHONE, false);
		assertThat(pending).isEmpty();
	}

	@Test
	void verifyOtp_newUser_createsUserRow() throws Exception {
		assertThat(userRepository.existsByPhoneE164(PHONE)).isFalse();

		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, OTP)))
				.andExpect(status().isOk());

		assertThat(userRepository.existsByPhoneE164(PHONE)).isTrue();
	}

	@Test
	void verifyOtp_newUser_createsActiveFreeSubscription() throws Exception {
		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, OTP)))
				.andExpect(status().isOk());

		var user = userRepository.findByPhoneE164(PHONE).orElseThrow();
		var sub = subscriptionRepository.findTopByUser_IdAndStatusOrderByCurrentPeriodEndDesc(
				user.getId(), SubscriptionStatus.ACTIVE);
		assertThat(sub).isPresent();
		assertThat(sub.get().getPlan().getPlanId()).isEqualTo(SubscriptionPlanIds.FREE);
	}

	@Test
	void verifyOtp_existingUser_doesNotAddSecondSubscription() throws Exception {
		userRepository.save(new odm.clarity.woleh.model.User(PHONE));
		long subsBefore = subscriptionRepository.count();

		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, OTP)))
				.andExpect(status().isOk());

		assertThat(subscriptionRepository.count()).isEqualTo(subsBefore);
	}

	// ── error cases ──────────────────────────────────────────────────────────

	@Test
	void verifyOtp_wrongOtp_returns400() throws Exception {
		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, "000000")))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("INVALID_OTP"));
	}

	@Test
	void verifyOtp_wrongOtp_incrementsAttemptCount() throws Exception {
		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, "000000")))
				.andExpect(status().isBadRequest());

		var challenges = otpChallengeRepository
				.findByPhoneE164AndConsumedOrderByCreatedAtDesc(PHONE, false);
		assertThat(challenges.get(0).getAttemptCount()).isEqualTo(1);
	}

	@Test
	void verifyOtp_expiredChallenge_returns400() throws Exception {
		otpChallengeRepository.deleteAll();
		// Create a challenge that has already expired
		createChallenge(PHONE, OTP, Instant.now().minusSeconds(1));

		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, OTP)))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("INVALID_OTP"));
	}

	@Test
	void verifyOtp_consumedOtp_returns400() throws Exception {
		// First verify succeeds (creates user)
		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, OTP)))
				.andExpect(status().isOk());

		// Second verify on same (now consumed) OTP must fail
		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, OTP)))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("INVALID_OTP"));
	}

	@Test
	void verifyOtp_exhaustedAttempts_returns400() throws Exception {
		// Exhaust all 5 allowed verify attempts with wrong OTPs
		for (int i = 0; i < 5; i++) {
			mockMvc.perform(post(VERIFY_URL)
					.contentType(MediaType.APPLICATION_JSON)
					.content(body(PHONE, "000000")))
					.andExpect(status().isBadRequest());
		}

		// Even the correct OTP must now fail (challenge exhausted)
		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, OTP)))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("INVALID_OTP"));
	}

	@Test
	void verifyOtp_noActiveOtp_returns400() throws Exception {
		otpChallengeRepository.deleteAll();

		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, OTP)))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("INVALID_OTP"));
	}

	@Test
	void verifyOtp_invalidPhoneFormat_returns400() throws Exception {
		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body("07911500100", OTP)))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void verifyOtp_invalidOtpFormat_returns400() throws Exception {
		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(body(PHONE, "12345")))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	// ── helpers ──────────────────────────────────────────────────────────────

	private void createChallenge(String phone, String otp, Instant expiresAt) {
		otpChallengeRepository.save(new OtpChallenge(phone, passwordEncoder.encode(otp), expiresAt));
	}

	private static String body(String phone, String otp) {
		return """
				{"phoneE164": "%s", "otp": "%s"}
				""".formatted(phone, otp);
	}
}
