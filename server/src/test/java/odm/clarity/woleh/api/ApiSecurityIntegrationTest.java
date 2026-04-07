package odm.clarity.woleh.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;

import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.security.JwtService;

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
class ApiSecurityIntegrationTest {

	@Autowired private MockMvc mockMvc;
	@Autowired private JwtService jwtService;
	@Autowired private UserRepository userRepository;

	@Test
	void me_withoutBearer_returns401Json() throws Exception {
		mockMvc.perform(get("/api/v1/me"))
				.andExpect(status().isUnauthorized())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
	}

	@Test
	void me_withValidToken_returns200Envelope() throws Exception {
		User user = userRepository.save(new User("+233241000001"));
		String token = jwtService.createAccessToken(user.getId(), Instant.now());

		mockMvc.perform(get("/api/v1/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"))
				.andExpect(jsonPath("$.data.profile.userId").value(String.valueOf(user.getId())));
	}

	@Test
	void unknownRoute_returns404Json() throws Exception {
		mockMvc.perform(get("/this-route-does-not-exist"))
				.andExpect(status().isNotFound())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("NOT_FOUND"));
	}
}
