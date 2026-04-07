package odm.clarity.woleh.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import odm.clarity.woleh.config.OtpProperties;
import odm.clarity.woleh.model.OtpChallenge;
import odm.clarity.woleh.repository.OtpChallengeRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class SendOtpIntegrationTest {

	private static final String SEND_OTP_URL = "/api/v1/auth/send-otp";
	private static final String PHONE = "+447911123456";

	@Autowired
	private MockMvc mockMvc;

	@Autowired
	private OtpChallengeRepository otpChallengeRepository;

	@Autowired
	private OtpProperties otpProperties;

	@BeforeEach
	void cleanUp() {
		otpChallengeRepository.deleteAll();
	}

	@Test
	void sendOtp_validPhone_returns200WithExpiresInSeconds() throws Exception {
		mockMvc.perform(post(SEND_OTP_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"phoneE164": "%s"}
						""".formatted(PHONE)))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"))
				.andExpect(jsonPath("$.message").value("OTP sent"))
				.andExpect(jsonPath("$.data.expiresInSeconds").value(otpProperties.ttl().toSeconds()));
	}

	@Test
	void sendOtp_validPhone_persistsHashedChallenge() throws Exception {
		mockMvc.perform(post(SEND_OTP_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"phoneE164": "%s"}
						""".formatted(PHONE)))
				.andExpect(status().isOk());

		var challenges = otpChallengeRepository.findByPhoneE164AndConsumedOrderByCreatedAtDesc(PHONE, false);
		assertThat(challenges).hasSize(1);
		OtpChallenge saved = challenges.get(0);
		assertThat(saved.getOtpHash()).isNotBlank();
		assertThat(saved.getOtpHash()).doesNotMatch("\\d{6}"); // must not be plaintext
		assertThat(saved.getExpiresAt()).isAfter(saved.getCreatedAt());
	}

	@Test
	void sendOtp_blankPhone_returns400() throws Exception {
		mockMvc.perform(post(SEND_OTP_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"phoneE164": ""}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void sendOtp_invalidE164_returns400() throws Exception {
		mockMvc.perform(post(SEND_OTP_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"phoneE164": "07911123456"}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void sendOtp_exceedsRateLimit_returns429() throws Exception {
		int max = otpProperties.rateLimitMaxSends();
		for (int i = 0; i < max; i++) {
			mockMvc.perform(post(SEND_OTP_URL)
					.contentType(MediaType.APPLICATION_JSON)
					.content("""
							{"phoneE164": "%s"}
							""".formatted(PHONE)))
					.andExpect(status().isOk());
		}

		mockMvc.perform(post(SEND_OTP_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"phoneE164": "%s"}
						""".formatted(PHONE)))
				.andExpect(status().isTooManyRequests())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("RATE_LIMITED"));
	}

	@Test
	void sendOtp_missingBody_returns400() throws Exception {
		mockMvc.perform(post(SEND_OTP_URL)
				.contentType(MediaType.APPLICATION_JSON))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"));
	}
}
