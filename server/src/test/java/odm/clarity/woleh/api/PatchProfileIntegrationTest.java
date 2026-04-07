package odm.clarity.woleh.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;

import odm.clarity.woleh.model.User;
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
class PatchProfileIntegrationTest {

	private static final String PATCH_URL = "/api/v1/me/profile";
	private static final String ME_URL = "/api/v1/me";
	private static final String PHONE = "+233241888001";

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired JwtService jwtService;

	private User user;
	private String bearerToken;

	@BeforeEach
	void setup() {
		userRepository.deleteAll();
		user = userRepository.save(new User(PHONE));
		bearerToken = "Bearer " + jwtService.createAccessToken(user.getId(), Instant.now());
	}

	// ── happy paths ──────────────────────────────────────────────────────────

	@Test
	void patchProfile_setDisplayName_returns200WithUpdatedName() throws Exception {
		mockMvc.perform(patch(PATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"displayName": "Ama Owusu"}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"))
				.andExpect(jsonPath("$.data.profile.displayName").value("Ama Owusu"));
	}

	@Test
	void patchProfile_setDisplayName_persistsAcrossGetMe() throws Exception {
		mockMvc.perform(patch(PATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"displayName": "Kofi Mensah"}
						"""))
				.andExpect(status().isOk());

		// Verify the name persists on subsequent GET /me
		mockMvc.perform(get(ME_URL).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.profile.displayName").value("Kofi Mensah"));
	}

	@Test
	void patchProfile_setDisplayName_persistsInDatabase() throws Exception {
		mockMvc.perform(patch(PATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"displayName": "Abena Asante"}
						"""))
				.andExpect(status().isOk());

		User updated = userRepository.findById(user.getId()).orElseThrow();
		assertThat(updated.getDisplayName()).isEqualTo("Abena Asante");
	}

	@Test
	void patchProfile_emptyBody_returns200WithNoChange() throws Exception {
		user.setDisplayName("Original");
		userRepository.save(user);

		mockMvc.perform(patch(PATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("{}"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.profile.displayName").value("Original"));
	}

	@Test
	void patchProfile_responseIncludesFullEntitlements() throws Exception {
		mockMvc.perform(patch(PATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"displayName": "Test User"}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.tier").value("free"))
				.andExpect(jsonPath("$.data.limits.placeWatchMax").value(5))
				.andExpect(jsonPath("$.data.permissions").isArray());
	}

	// ── error cases ──────────────────────────────────────────────────────────

	@Test
	void patchProfile_sendingPhoneE164_returns400() throws Exception {
		mockMvc.perform(patch(PATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"displayName": "Ama", "phoneE164": "+233241888001"}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void patchProfile_displayNameTooLong_returns400() throws Exception {
		String tooLong = "A".repeat(256);
		mockMvc.perform(patch(PATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"displayName": "%s"}
						""".formatted(tooLong)))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void patchProfile_displayNameEmpty_returns400() throws Exception {
		mockMvc.perform(patch(PATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"displayName": ""}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void patchProfile_noToken_returns401() throws Exception {
		mockMvc.perform(patch(PATCH_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"displayName": "Ama"}
						"""))
				.andExpect(status().isUnauthorized());
	}
}
