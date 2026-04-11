package odm.clarity.woleh.location;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;

import odm.clarity.woleh.model.User;
import odm.clarity.woleh.ratelimit.LocationPublishRateLimiter;
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
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
@TestPropertySource(properties = "woleh.ratelimit.location-publish.min-interval-millis=200")
class LocationPublishIntegrationTest {

	private static final String PHONE = "+233201111099";
	private static final String LOCATION_URL = "/api/v1/me/location";
	private static final String SHARING_URL = "/api/v1/me/location-sharing";

	private static final List<String> PAID_PERMS = List.of(
			"woleh.account.profile", "woleh.plans.read",
			"woleh.place.watch", "woleh.place.broadcast");

	private static final String BODY_ACC = "{\"latitude\":5.6037,\"longitude\":-0.1870}";

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired JwtService jwtService;
	@Autowired LocationPublishRateLimiter locationPublishRateLimiter;

	@MockBean EntitlementService entitlementService;

	private User user;
	private String bearer;

	@BeforeEach
	void setup() {
		userRepository.deleteAll();
		locationPublishRateLimiter.clearForTesting();

		user = userRepository.save(new User(PHONE));
		bearer = "Bearer " + jwtService.createAccessToken(user.getId(), Instant.now());

		when(entitlementService.computeEntitlements(user.getId())).thenReturn(paidEntitlements());
	}

	@Test
	void postLocation_whenSharingOff_returns403() throws Exception {
		user.setLocationSharingEnabled(false);
		userRepository.save(user);

		mockMvc.perform(post(LOCATION_URL)
						.header(HttpHeaders.AUTHORIZATION, bearer)
						.contentType(MediaType.APPLICATION_JSON)
						.content(BODY_ACC))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.code").value("LOCATION_SHARING_OFF"));
	}

	@Test
	void postLocation_whenDefaultSharingOn_ok() throws Exception {
		mockMvc.perform(post(LOCATION_URL)
						.header(HttpHeaders.AUTHORIZATION, bearer)
						.contentType(MediaType.APPLICATION_JSON)
						.content(BODY_ACC))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"));
	}

	@Test
	void disableSharing_thenPost_forbidden() throws Exception {
		user.setLocationSharingEnabled(true);
		userRepository.save(user);

		mockMvc.perform(put(SHARING_URL)
						.header(HttpHeaders.AUTHORIZATION, bearer)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"enabled\":false}"))
				.andExpect(status().isOk());

		mockMvc.perform(post(LOCATION_URL)
						.header(HttpHeaders.AUTHORIZATION, bearer)
						.contentType(MediaType.APPLICATION_JSON)
						.content(BODY_ACC))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.code").value("LOCATION_SHARING_OFF"));
	}

	@Test
	void secondPostWithinInterval_returns429() throws Exception {
		mockMvc.perform(post(LOCATION_URL)
						.header(HttpHeaders.AUTHORIZATION, bearer)
						.contentType(MediaType.APPLICATION_JSON)
						.content(BODY_ACC))
				.andExpect(status().isOk());

		mockMvc.perform(post(LOCATION_URL)
						.header(HttpHeaders.AUTHORIZATION, bearer)
						.contentType(MediaType.APPLICATION_JSON)
						.content(BODY_ACC))
				.andExpect(status().isTooManyRequests())
				.andExpect(jsonPath("$.code").value("RATE_LIMITED"));
	}

	private static Entitlements paidEntitlements() {
		return new Entitlements(
				PAID_PERMS, "paid", 50, 50, "active", null, false);
	}
}
