package odm.clarity.woleh.places;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;

import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.UserPlaceListRepository;
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
class WatchListIntegrationTest {

	private static final String WATCH_URL = "/api/v1/me/places/watch";
	private static final String PHONE = "+233241999021";

	// Free-tier permissions — all free users have woleh.place.watch.
	private static final List<String> FREE_PERMS = List.of(
			"woleh.account.profile", "woleh.plans.read", "woleh.place.watch");

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired UserPlaceListRepository placeListRepository;
	@Autowired JwtService jwtService;

	/**
	 * MockBean so we can control permissions precisely per test.
	 * Default stub: free-tier entitlements (watch limit = 5, no broadcast).
	 */
	@MockBean EntitlementService entitlementService;

	private User user;
	private String bearerToken;

	@BeforeEach
	void setup() {
		placeListRepository.deleteAll();
		userRepository.deleteAll();

		user = userRepository.save(new User(PHONE));
		bearerToken = "Bearer " + jwtService.createAccessToken(user.getId(), Instant.now());

		// Default: free-tier entitlements
		stubFreeEntitlements();
	}

	// ── auth guard ────────────────────────────────────────────────────────

	@Test
	void watchList_get_withoutToken_returns401() throws Exception {
		mockMvc.perform(get(WATCH_URL))
				.andExpect(status().isUnauthorized())
				.andExpect(jsonPath("$.result").value("ERROR"));
	}

	@Test
	void watchList_put_withoutToken_returns401() throws Exception {
		mockMvc.perform(put(WATCH_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Circle"]}
						"""))
				.andExpect(status().isUnauthorized());
	}

	// ── permission guard ──────────────────────────────────────────────────

	@Test
	void watchList_get_missingPermission_returns403() throws Exception {
		// Override: entitlements without woleh.place.watch
		stubEntitlements(List.of("woleh.account.profile"), 0, 0);

		mockMvc.perform(get(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("PERMISSION_DENIED"));
	}

	@Test
	void watchList_put_missingPermission_returns403() throws Exception {
		stubEntitlements(List.of("woleh.account.profile"), 0, 0);

		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Circle"]}
						"""))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.code").value("PERMISSION_DENIED"));
	}

	// ── validation errors ─────────────────────────────────────────────────

	@Test
	void watchList_put_emptyName_returns400() throws Exception {
		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":[""]}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void watchList_put_blankName_returns400() throws Exception {
		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["   "]}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void watchList_put_tooLongName_returns400() throws Exception {
		// Name with 201 code points — one over the limit
		String tooLong = "a".repeat(201);

		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"names\":[\"" + tooLong + "\"]}"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void watchList_put_missingNamesField_returns400() throws Exception {
		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("{}"))
				.andExpect(status().isBadRequest());
	}

	// ── limit enforcement ─────────────────────────────────────────────────

	@Test
	void watchList_put_freeUserExceedsLimit_returns403() throws Exception {
		// Free tier allows 5 names; sending 6 should be rejected.
		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["A","B","C","D","E","F"]}
						"""))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("OVER_LIMIT"));
	}

	@Test
	void watchList_put_freeUserAtExactLimit_returns200() throws Exception {
		// Exactly 5 names — must be accepted.
		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["A","B","C","D","E"]}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"));
	}

	// ── happy path ────────────────────────────────────────────────────────

	@Test
	void watchList_get_whenNoListSaved_returnsEmptyArray() throws Exception {
		mockMvc.perform(get(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"))
				.andExpect(jsonPath("$.data.names").isArray())
				.andExpect(jsonPath("$.data.names").isEmpty());
	}

	@Test
	void watchList_putThenGet_roundTrip() throws Exception {
		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Accra Central","Circle"]}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.names[0]").value("Accra Central"))
				.andExpect(jsonPath("$.data.names[1]").value("Circle"));

		mockMvc.perform(get(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.names[0]").value("Accra Central"))
				.andExpect(jsonPath("$.data.names[1]").value("Circle"));
	}

	@Test
	void watchList_put_replacesExistingList() throws Exception {
		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Old Stop"]}
						"""))
				.andExpect(status().isOk());

		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["New Stop"]}
						"""))
				.andExpect(status().isOk());

		mockMvc.perform(get(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(jsonPath("$.data.names[0]").value("New Stop"))
				.andExpect(jsonPath("$.data.names.length()").value(1));
	}

	@Test
	void watchList_put_emptyList_clearsExisting() throws Exception {
		// Save a list
		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Circle"]}
						"""))
				.andExpect(status().isOk());

		// Clear with empty list
		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":[]}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.names").isEmpty());

		mockMvc.perform(get(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(jsonPath("$.data.names").isEmpty());
	}

	// ── dedupe behaviour ──────────────────────────────────────────────────

	@Test
	void watchList_put_dedupesByNormalizedForm_keepsFirstOccurrence() throws Exception {
		// "Circle" and "circle " normalize to the same form; only the first is kept.
		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Circle","circle "]}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.names.length()").value(1))
				.andExpect(jsonPath("$.data.names[0]").value("Circle"));
	}

	@Test
	void watchList_put_dedupedCountEnforcedAgainstLimit() throws Exception {
		// 6 names but 2 pairs dedupe to the same, leaving 4 unique — under the limit of 5.
		mockMvc.perform(put(WATCH_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["A","a","B","b","C","D"]}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.names.length()").value(4));
	}

	// ── helpers ───────────────────────────────────────────────────────────

	private void stubFreeEntitlements() {
		stubEntitlements(FREE_PERMS, 5, 0);
	}

	private void stubEntitlements(List<String> perms, int watchMax, int broadcastMax) {
		Entitlements ent = new Entitlements(perms, perms.contains("woleh.place.broadcast") ? "paid" : "free",
				watchMax, broadcastMax, "none", null, false);
		when(entitlementService.computeEntitlements(user.getId())).thenReturn(ent);
	}
}
