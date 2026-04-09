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
class BroadcastListIntegrationTest {

	private static final String BROADCAST_URL = "/api/v1/me/places/broadcast";
	private static final String PHONE = "+233241999031";

	private static final List<String> PAID_PERMS = List.of(
			"woleh.account.profile", "woleh.plans.read",
			"woleh.place.watch", "woleh.place.broadcast");

	private static final List<String> FREE_PERMS = List.of(
			"woleh.account.profile", "woleh.plans.read", "woleh.place.watch");

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired UserPlaceListRepository placeListRepository;
	@Autowired JwtService jwtService;

	@MockBean EntitlementService entitlementService;

	private User user;
	private String bearerToken;

	@BeforeEach
	void setup() {
		placeListRepository.deleteAll();
		userRepository.deleteAll();

		user = userRepository.save(new User(PHONE));
		bearerToken = "Bearer " + jwtService.createAccessToken(user.getId(), Instant.now());

		// Default: paid-tier (has woleh.place.broadcast with limit 50)
		stubPaidEntitlements(50);
	}

	// ── auth guard ────────────────────────────────────────────────────────

	@Test
	void broadcastList_get_withoutToken_returns401() throws Exception {
		mockMvc.perform(get(BROADCAST_URL))
				.andExpect(status().isUnauthorized())
				.andExpect(jsonPath("$.result").value("ERROR"));
	}

	@Test
	void broadcastList_put_withoutToken_returns401() throws Exception {
		mockMvc.perform(put(BROADCAST_URL)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Stop A"]}
						"""))
				.andExpect(status().isUnauthorized());
	}

	// ── permission guard (free user lacks woleh.place.broadcast) ─────────

	@Test
	void broadcastList_get_freeUser_returns403() throws Exception {
		stubFreeEntitlements();

		mockMvc.perform(get(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.result").value("ERROR"))
				.andExpect(jsonPath("$.code").value("PERMISSION_DENIED"));
	}

	@Test
	void broadcastList_put_freeUser_returns403() throws Exception {
		stubFreeEntitlements();

		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Stop A"]}
						"""))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.code").value("PERMISSION_DENIED"));
	}

	// ── validation errors ─────────────────────────────────────────────────

	@Test
	void broadcastList_put_emptyName_returns400() throws Exception {
		mockMvc.perform(put(BROADCAST_URL)
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
	void broadcastList_put_blankName_returns400() throws Exception {
		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["   "]}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void broadcastList_put_tooLongName_returns400() throws Exception {
		String tooLong = "a".repeat(201);

		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"names\":[\"" + tooLong + "\"]}"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	// ── duplicate rejection (broadcast-specific) ──────────────────────────

	@Test
	void broadcastList_put_exactDuplicates_returns400() throws Exception {
		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Circle","Circle"]}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void broadcastList_put_caseVariantDuplicates_returns400() throws Exception {
		// "circle" and "Circle" normalize to the same form — treated as duplicate.
		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Circle","circle"]}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	@Test
	void broadcastList_put_whitespaceVariantDuplicates_returns400() throws Exception {
		// "Stop A" and "stop  a" normalize to the same form.
		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Stop A","stop  a"]}
						"""))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
	}

	// ── limit enforcement ─────────────────────────────────────────────────

	@Test
	void broadcastList_put_exceedsLimit_returns403() throws Exception {
		stubPaidEntitlements(2); // paid user with a limit of 2

		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Stop A","Stop B","Stop C"]}
						"""))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.code").value("OVER_LIMIT"));
	}

	@Test
	void broadcastList_put_atExactLimit_returns200() throws Exception {
		stubPaidEntitlements(3);

		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Stop A","Stop B","Stop C"]}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"));
	}

	// ── happy path ────────────────────────────────────────────────────────

	@Test
	void broadcastList_get_whenNoListSaved_returnsEmptyArray() throws Exception {
		mockMvc.perform(get(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"))
				.andExpect(jsonPath("$.data.names").isArray())
				.andExpect(jsonPath("$.data.names").isEmpty());
	}

	@Test
	void broadcastList_putThenGet_roundTrip() throws Exception {
		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Stop A","Stop B","Stop C"]}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.names[0]").value("Stop A"))
				.andExpect(jsonPath("$.data.names[1]").value("Stop B"))
				.andExpect(jsonPath("$.data.names[2]").value("Stop C"));

		mockMvc.perform(get(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.names[0]").value("Stop A"))
				.andExpect(jsonPath("$.data.names[1]").value("Stop B"))
				.andExpect(jsonPath("$.data.names[2]").value("Stop C"));
	}

	@Test
	void broadcastList_put_orderIsPreserved() throws Exception {
		// Deliberately non-alphabetical to confirm insertion order is kept, not sorted.
		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Tema","Circle","Kaneshie","Accra Central"]}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.names[0]").value("Tema"))
				.andExpect(jsonPath("$.data.names[1]").value("Circle"))
				.andExpect(jsonPath("$.data.names[2]").value("Kaneshie"))
				.andExpect(jsonPath("$.data.names[3]").value("Accra Central"));
	}

	@Test
	void broadcastList_put_replacesExistingList() throws Exception {
		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Old Stop"]}
						"""))
				.andExpect(status().isOk());

		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["New Stop A","New Stop B"]}
						"""))
				.andExpect(status().isOk());

		mockMvc.perform(get(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(jsonPath("$.data.names.length()").value(2))
				.andExpect(jsonPath("$.data.names[0]").value("New Stop A"));
	}

	@Test
	void broadcastList_put_emptyList_clearsExisting() throws Exception {
		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":["Stop A"]}
						"""))
				.andExpect(status().isOk());

		mockMvc.perform(put(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken)
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
						{"names":[]}
						"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.names").isEmpty());

		mockMvc.perform(get(BROADCAST_URL)
				.header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(jsonPath("$.data.names").isEmpty());
	}

	// ── helpers ───────────────────────────────────────────────────────────

	private void stubPaidEntitlements(int broadcastMax) {
		Entitlements ent = new Entitlements(PAID_PERMS, "paid", 50, broadcastMax,
				"active", Instant.now().plusSeconds(86400).toString(), false);
		when(entitlementService.computeEntitlements(user.getId())).thenReturn(ent);
	}

	private void stubFreeEntitlements() {
		Entitlements ent = new Entitlements(FREE_PERMS, "free", 5, 0, "none", null, false);
		when(entitlementService.computeEntitlements(user.getId())).thenReturn(ent);
	}
}
