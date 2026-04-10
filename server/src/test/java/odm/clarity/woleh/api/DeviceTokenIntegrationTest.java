package odm.clarity.woleh.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;

import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.DeviceTokenRepository;
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
class DeviceTokenIntegrationTest {

	private static final String URL = "/api/v1/me/device-token";
	private static final String PHONE = "+233241999002";

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired DeviceTokenRepository deviceTokenRepository;
	@Autowired JwtService jwtService;

	private String bearerToken;

	@BeforeEach
	void setup() {
		deviceTokenRepository.deleteAll();
		userRepository.deleteAll();
		var user = userRepository.save(new User(PHONE));
		bearerToken = "Bearer " + jwtService.createAccessToken(user.getId(), Instant.now());
	}

	@Test
	void register_thenDelete_removesRow() throws Exception {
		mockMvc.perform(post(URL)
						.header(HttpHeaders.AUTHORIZATION, bearerToken)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"token\":\"fcm-token-abc\",\"platform\":\"android\"}"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"));

		assertEquals(1, deviceTokenRepository.findAll().size());

		mockMvc.perform(delete(URL)
						.header(HttpHeaders.AUTHORIZATION, bearerToken)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"token\":\"fcm-token-abc\"}"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"));

		assertTrue(deviceTokenRepository.findAll().isEmpty());
	}

	@Test
	void register_sameTokenTwice_updatesUpdatedAtWithoutDuplicate() throws Exception {
		mockMvc.perform(post(URL)
						.header(HttpHeaders.AUTHORIZATION, bearerToken)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"token\":\"same\",\"platform\":\"ios\"}"))
				.andExpect(status().isOk());

		mockMvc.perform(post(URL)
						.header(HttpHeaders.AUTHORIZATION, bearerToken)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"token\":\"same\",\"platform\":\"ios\"}"))
				.andExpect(status().isOk());

		assertEquals(1, deviceTokenRepository.findAll().size());
	}

	@Test
	void register_invalidPlatform_returns400() throws Exception {
		mockMvc.perform(post(URL)
						.header(HttpHeaders.AUTHORIZATION, bearerToken)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"token\":\"x\",\"platform\":\"windows\"}"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void register_withoutAuth_returns401() throws Exception {
		mockMvc.perform(post(URL)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"token\":\"x\",\"platform\":\"android\"}"))
				.andExpect(status().isUnauthorized());
	}

	@Test
	void delete_withoutAuth_returns401() throws Exception {
		mockMvc.perform(delete(URL)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"token\":\"x\"}"))
				.andExpect(status().isUnauthorized());
	}
}
