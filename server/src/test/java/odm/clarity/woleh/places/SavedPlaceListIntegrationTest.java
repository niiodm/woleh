package odm.clarity.woleh.places;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;

import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.repository.UserSavedPlaceListRepository;
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
class SavedPlaceListIntegrationTest {

	private static final String BASE = "/api/v1/me/saved-place-lists";
	private static final String PHONE = "+233241999031";

	private static final List<String> FREE_PERMS = List.of(
			"woleh.account.profile", "woleh.plans.read", "woleh.place.watch");

	@Autowired MockMvc mockMvc;
	@Autowired UserRepository userRepository;
	@Autowired UserSavedPlaceListRepository savedPlaceListRepository;
	@Autowired JwtService jwtService;

	@MockBean EntitlementService entitlementService;

	private User user;
	private String bearerToken;

	@BeforeEach
	void setup() {
		savedPlaceListRepository.deleteAll();
		userRepository.deleteAll();
		user = userRepository.save(new User(PHONE));
		bearerToken = "Bearer " + jwtService.createAccessToken(user.getId(), Instant.now());
		stubFreeEntitlements();
	}

	private void stubFreeEntitlements() {
		Entitlements ent = new Entitlements(FREE_PERMS, "free", 5, 0, 10, "none", null, false);
		when(entitlementService.computeEntitlements(user.getId())).thenReturn(ent);
	}

	private void stubNoPlacePerms() {
		Entitlements ent = new Entitlements(
				List.of("woleh.account.profile", "woleh.plans.read"),
				"free", 0, 0, 10, "none", null, false);
		when(entitlementService.computeEntitlements(user.getId())).thenReturn(ent);
	}

	private void stubSavedListCap(int cap) {
		Entitlements ent = new Entitlements(FREE_PERMS, "free", 5, 0, cap, "none", null, false);
		when(entitlementService.computeEntitlements(user.getId())).thenReturn(ent);
	}

	@Test
	void list_withoutAuth_returns401() throws Exception {
		mockMvc.perform(get(BASE))
				.andExpect(status().isUnauthorized());
	}

	@Test
	void list_empty_returns200() throws Exception {
		mockMvc.perform(get(BASE).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"))
				.andExpect(jsonPath("$.data.length()").value(0));
	}

	@Test
	void create_get_publicRoundTrip() throws Exception {
		mockMvc.perform(post(BASE)
						.header(HttpHeaders.AUTHORIZATION, bearerToken)
						.contentType(MediaType.APPLICATION_JSON)
						.content("""
								{"title":"Weekend","names":["Accra","Kumasi"]}
								"""))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.title").value("Weekend"))
				.andExpect(jsonPath("$.data.names.length()").value(2))
				.andExpect(jsonPath("$.data.shareToken").isString());

		mockMvc.perform(get(BASE).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.length()").value(1))
				.andExpect(jsonPath("$.data[0].placeCount").value(2))
				.andExpect(jsonPath("$.data[0].title").value("Weekend"));

		String token = savedPlaceListRepository.findAll().get(0).getShareToken();

		mockMvc.perform(get("/api/v1/public/saved-place-lists/" + token))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.title").value("Weekend"))
				.andExpect(jsonPath("$.data.names[0]").value("Accra"))
				.andExpect(jsonPath("$.data.names[1]").value("Kumasi"));
	}

	@Test
	void get_unknownId_returns404() throws Exception {
		mockMvc.perform(get(BASE + "/99999").header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isNotFound())
				.andExpect(jsonPath("$.code").value("NOT_FOUND"));
	}

	@Test
	void public_unknownToken_returns404() throws Exception {
		mockMvc.perform(get("/api/v1/public/saved-place-lists/nonexistent-token-xxxxxxxx"))
				.andExpect(status().isNotFound());
	}

	@Test
	void noPlacePermission_returns403() throws Exception {
		stubNoPlacePerms();
		mockMvc.perform(get(BASE).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.code").value("PERMISSION_DENIED"));
	}

	@Test
	void tooManySavedLists_returns403() throws Exception {
		stubSavedListCap(1);
		mockMvc.perform(post(BASE)
						.header(HttpHeaders.AUTHORIZATION, bearerToken)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"title\":\"A\",\"names\":[\"One\"]}"))
				.andExpect(status().isOk());
		mockMvc.perform(post(BASE)
						.header(HttpHeaders.AUTHORIZATION, bearerToken)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"title\":\"B\",\"names\":[\"Two\"]}"))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.code").value("OVER_LIMIT"));
	}

	@Test
	void put_replace_then_delete() throws Exception {
		mockMvc.perform(post(BASE)
						.header(HttpHeaders.AUTHORIZATION, bearerToken)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"title\":\"T\",\"names\":[\"A\"]}"))
				.andExpect(status().isOk());
		long id = savedPlaceListRepository.findAll().get(0).getId();

		mockMvc.perform(put(BASE + "/" + id)
						.header(HttpHeaders.AUTHORIZATION, bearerToken)
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"title\":\"T2\",\"names\":[\"B\",\"C\"]}"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data.title").value("T2"))
				.andExpect(jsonPath("$.data.names.length()").value(2));

		mockMvc.perform(delete(BASE + "/" + id).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isOk());

		mockMvc.perform(get(BASE + "/" + id).header(HttpHeaders.AUTHORIZATION, bearerToken))
				.andExpect(status().isNotFound());
	}
}
