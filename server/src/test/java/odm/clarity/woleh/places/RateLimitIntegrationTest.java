package odm.clarity.woleh.places;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;

import odm.clarity.woleh.model.User;
import odm.clarity.woleh.ratelimit.PlaceListRateLimiter;
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

/**
 * Integration tests for place-list rate limiting (Phase 3, Step 2.1).
 * Sets a low limit of 2 requests/minute so tests can trigger 429 without many calls.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
@TestPropertySource(properties = "woleh.ratelimit.place-list.requests-per-minute=2")
class RateLimitIntegrationTest {

	private static final String WATCH_URL = "/api/v1/me/places/watch";
	private static final String BROADCAST_URL = "/api/v1/me/places/broadcast";
	private static final String PHONE_A = "+233201111001";
	private static final String PHONE_B = "+233201111002";

	private static final List<String> PAID_PERMS = List.of(
			"woleh.account.profile", "woleh.plans.read",
			"woleh.place.watch", "woleh.place.broadcast");

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired JwtService jwtService;
	@Autowired PlaceListRateLimiter rateLimiter;

	@MockBean EntitlementService entitlementService;

	private User userA;
	private String tokenA;
	private User userB;
	private String tokenB;

	@BeforeEach
	void setup() {
		userRepository.deleteAll();

		userA = userRepository.save(new User(PHONE_A));
		tokenA = "Bearer " + jwtService.createAccessToken(userA.getId(), Instant.now());

		userB = userRepository.save(new User(PHONE_B));
		tokenB = "Bearer " + jwtService.createAccessToken(userB.getId(), Instant.now());

		stubPaidEntitlements(userA.getId());
		stubPaidEntitlements(userB.getId());

		// Reset in-memory rate-limit state so tests are independent
		rateLimiter.clearForTesting();
	}

	// ── watch list ────────────────────────────────────────────────────────────

	@Test
	void putWatch_withinLimit_succeeds() throws Exception {
		putWatch(tokenA).andExpect(status().isOk());
		putWatch(tokenA).andExpect(status().isOk());
	}

	@Test
	void putWatch_exceedsLimit_returns429WithRetryAfter() throws Exception {
		putWatch(tokenA).andExpect(status().isOk());
		putWatch(tokenA).andExpect(status().isOk());

		putWatch(tokenA)
				.andExpect(status().isTooManyRequests())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("RATE_LIMITED"))
				.andExpect(header().exists("Retry-After"));
	}

	// ── broadcast list ────────────────────────────────────────────────────────

	@Test
	void putBroadcast_exceedsLimit_returns429WithRetryAfter() throws Exception {
		putBroadcast(tokenA).andExpect(status().isOk());
		putBroadcast(tokenA).andExpect(status().isOk());

		putBroadcast(tokenA)
				.andExpect(status().isTooManyRequests())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("RATE_LIMITED"))
				.andExpect(header().exists("Retry-After"));
	}

	// ── isolation ─────────────────────────────────────────────────────────────

	@Test
	void watchLimit_doesNotAffectBroadcast() throws Exception {
		putWatch(tokenA).andExpect(status().isOk());
		putWatch(tokenA).andExpect(status().isOk());
		putWatch(tokenA).andExpect(status().isTooManyRequests());

		// Broadcast bucket for the same user is separate — should still succeed
		putBroadcast(tokenA).andExpect(status().isOk());
		putBroadcast(tokenA).andExpect(status().isOk());
	}

	@Test
	void userALimit_doesNotAffectUserB() throws Exception {
		putWatch(tokenA).andExpect(status().isOk());
		putWatch(tokenA).andExpect(status().isOk());
		putWatch(tokenA).andExpect(status().isTooManyRequests());

		// User B should be unaffected
		putWatch(tokenB).andExpect(status().isOk());
		putWatch(tokenB).andExpect(status().isOk());
	}

	// ── helpers ───────────────────────────────────────────────────────────────

	private org.springframework.test.web.servlet.ResultActions putWatch(String bearer) throws Exception {
		return mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearer)
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"names\":[\"Circle\"]}"));
	}

	private org.springframework.test.web.servlet.ResultActions putBroadcast(String bearer) throws Exception {
		return mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearer)
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"names\":[\"Circle\"]}"));
	}

	private void stubPaidEntitlements(Long userId) {
		Entitlements ent = new Entitlements(
				PAID_PERMS, "paid", 50, 50, "active", null, false);
		when(entitlementService.computeEntitlements(userId)).thenReturn(ent);
	}
}
