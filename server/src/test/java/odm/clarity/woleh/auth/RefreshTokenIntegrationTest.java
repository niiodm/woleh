package odm.clarity.woleh.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;

import odm.clarity.woleh.model.OtpChallenge;
import odm.clarity.woleh.model.RefreshToken;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.OtpChallengeRepository;
import odm.clarity.woleh.repository.PlanRepository;
import odm.clarity.woleh.repository.RefreshTokenRepository;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.security.JwtService;
import odm.clarity.woleh.support.PlanCatalogTestHelper;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Integration tests for the refresh token flow (FR-A2, Phase 3 Step 2.4).
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class RefreshTokenIntegrationTest {

	private static final String VERIFY_URL = "/api/v1/auth/verify-otp";
	private static final String REFRESH_URL = "/api/v1/auth/refresh";
	private static final String LOGOUT_URL = "/api/v1/auth/logout";
	private static final String PHONE = "+447911500200";
	private static final String OTP = "112233";

	@Autowired MockMvc mockMvc;
	@Autowired ObjectMapper objectMapper;
	@Autowired OtpChallengeRepository otpChallengeRepository;
	@Autowired UserRepository userRepository;
	@Autowired PlanRepository planRepository;
	@Autowired RefreshTokenRepository refreshTokenRepository;
	@Autowired PasswordEncoder passwordEncoder;
	@Autowired JwtService jwtService;

	@BeforeEach
	void seed() {
		refreshTokenRepository.deleteAll();
		otpChallengeRepository.deleteAll();
		userRepository.deleteAll();
		PlanCatalogTestHelper.ensureDefaultPlans(planRepository);
		otpChallengeRepository.save(
				new OtpChallenge(PHONE, passwordEncoder.encode(OTP), Instant.now().plusSeconds(300)));
	}

	// ── verify-otp now issues refresh token ──────────────────────────────────

	@Test
	void verifyOtp_returnsRefreshToken() throws Exception {
		mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(verifyBody(PHONE, OTP)))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.refreshToken").isNotEmpty());
	}

	// ── refresh: happy path ───────────────────────────────────────────────────

	@Test
	void refresh_withValidToken_returnsNewTokenPair() throws Exception {
		String rawRefreshToken = verifyAndGetRefreshToken();

		mockMvc.perform(post(REFRESH_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(refreshBody(rawRefreshToken)))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.accessToken").isNotEmpty())
				.andExpect(jsonPath("$.data.refreshToken").isNotEmpty())
				.andExpect(jsonPath("$.data.expiresIn").isNumber());
	}

	// ── refresh: rejection cases ──────────────────────────────────────────────

	@Test
	void refresh_withOldToken_afterRotation_returns401() throws Exception {
		String rawRefreshToken = verifyAndGetRefreshToken();

		// First rotation succeeds
		mockMvc.perform(post(REFRESH_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(refreshBody(rawRefreshToken)))
				.andExpect(status().isOk());

		// Old token is now revoked — must return 401
		mockMvc.perform(post(REFRESH_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(refreshBody(rawRefreshToken)))
				.andExpect(status().isUnauthorized())
				.andExpect(jsonPath("$.code").value("INVALID_REFRESH_TOKEN"));
	}

	@Test
	void refresh_withUnknownToken_returns401() throws Exception {
		mockMvc.perform(post(REFRESH_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(refreshBody("completely-unknown-token-value")))
				.andExpect(status().isUnauthorized())
				.andExpect(jsonPath("$.code").value("INVALID_REFRESH_TOKEN"));
	}

	@Test
	void refresh_withExpiredToken_returns401() throws Exception {
		// Insert an already-expired refresh token directly
		User user = userRepository.save(new User("+447911500201"));
		String raw = jwtService.generateRefreshToken();
		String hash = jwtService.hashToken(raw);
		refreshTokenRepository.save(new RefreshToken(user.getId(), hash, Instant.now().minusSeconds(1)));

		mockMvc.perform(post(REFRESH_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(refreshBody(raw)))
				.andExpect(status().isUnauthorized())
				.andExpect(jsonPath("$.code").value("INVALID_REFRESH_TOKEN"));
	}

	// ── logout ────────────────────────────────────────────────────────────────

	@Test
	void logout_revokesRefreshToken_subsequentRefreshFails() throws Exception {
		String rawRefreshToken = verifyAndGetRefreshToken();

		mockMvc.perform(post(LOGOUT_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"refreshToken\":\"" + rawRefreshToken + "\"}"))
				.andExpect(status().isOk());

		// After logout the token's owner has no valid refresh tokens — refresh must fail
		mockMvc.perform(post(REFRESH_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(refreshBody(rawRefreshToken)))
				.andExpect(status().isUnauthorized());
	}

	@Test
	void logout_withNoBody_returns200() throws Exception {
		mockMvc.perform(post(LOGOUT_URL)
				.contentType(MediaType.APPLICATION_JSON))
				.andExpect(status().isOk());
	}

	// ── helpers ──────────────────────────────────────────────────────────────

	private String verifyAndGetRefreshToken() throws Exception {
		MvcResult result = mockMvc.perform(post(VERIFY_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content(verifyBody(PHONE, OTP)))
				.andExpect(status().isOk())
				.andReturn();

		String json = result.getResponse().getContentAsString();
		JsonNode data = objectMapper.readTree(json).path("data");
		String raw = data.path("refreshToken").asText();
		assertThat(raw).isNotBlank();
		return raw;
	}

	private static String verifyBody(String phone, String otp) {
		return """
				{"phoneE164": "%s", "otp": "%s"}
				""".formatted(phone, otp);
	}

	private static String refreshBody(String refreshToken) {
		return """
				{"refreshToken": "%s"}
				""".formatted(refreshToken);
	}
}
