package odm.clarity.woleh.location;

import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;

import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.security.JwtService;
import odm.clarity.woleh.subscription.EntitlementService;
import odm.clarity.woleh.subscription.Entitlements;

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
class LocationPublishPermissionIntegrationTest {

	private static final String PHONE = "+233201111088";

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired JwtService jwtService;

	@MockBean EntitlementService entitlementService;

	private String bearer;

	@BeforeEach
	void setup() {
		userRepository.deleteAll();
		User user = userRepository.save(new User(PHONE));
		bearer = "Bearer " + jwtService.createAccessToken(user.getId(), Instant.now());

		when(entitlementService.computeEntitlements(anyLong())).thenReturn(
				new Entitlements(
						List.of("woleh.account.profile", "woleh.plans.read"),
						"free",
						0,
						0,
						10,
						"none",
						null,
						false));
	}

	@Test
	void postLocation_withoutWatchOrBroadcast_forbidden() throws Exception {
		mockMvc.perform(post("/api/v1/me/location")
						.header(HttpHeaders.AUTHORIZATION, bearer)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"latitude\":5.6,\"longitude\":-0.2}"))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.code").value("PERMISSION_DENIED"));
	}

	@Test
	void putLocationSharing_withoutWatchOrBroadcast_forbidden() throws Exception {
		mockMvc.perform(put("/api/v1/me/location-sharing")
						.header(HttpHeaders.AUTHORIZATION, bearer)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"enabled\":true}"))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.code").value("PERMISSION_DENIED"));
	}
}
