package odm.clarity.woleh.subscription;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.repository.PlanRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class PlansIntegrationTest {

	private static final String PLANS_URL = "/api/v1/subscription/plans";

	@Autowired MockMvc mockMvc;
	@Autowired PlanRepository planRepository;

	@BeforeEach
	void setup() {
		planRepository.deleteAll();
		planRepository.save(new Plan(
				"woleh_free", "Free",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				0, "GHS", 999999999, 999999999, true));
		planRepository.save(new Plan(
				"woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.account.profile", "woleh.plans.read",
						"woleh.place.watch", "woleh.place.broadcast"),
				100, "GHS", 999999999, 999999999, true));
	}

	// ── accessibility ─────────────────────────────────────────────────────────

	@Test
	void plans_unauthenticated_returns200() throws Exception {
		mockMvc.perform(get(PLANS_URL))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.result").value("SUCCESS"));
	}

	// ── response shape ────────────────────────────────────────────────────────

	@Test
	void plans_returnsBothActivePlans() throws Exception {
		mockMvc.perform(get(PLANS_URL))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.data").isArray())
				.andExpect(jsonPath("$.data.length()").value(2));
	}

	@Test
	void plans_orderedByPriceAscendingFreeFirst() throws Exception {
		mockMvc.perform(get(PLANS_URL))
				.andExpect(jsonPath("$.data[0].planId").value("woleh_free"))
				.andExpect(jsonPath("$.data[1].planId").value("woleh_paid_monthly"));
	}

	@Test
	void plans_freePlanShape() throws Exception {
		mockMvc.perform(get(PLANS_URL))
				.andExpect(jsonPath("$.data[0].planId").value("woleh_free"))
				.andExpect(jsonPath("$.data[0].displayName").value("Free"))
				.andExpect(jsonPath("$.data[0].price.amountMinor").value(0))
				.andExpect(jsonPath("$.data[0].price.currency").value("GHS"))
				.andExpect(jsonPath("$.data[0].limits.placeWatchMax").value(999999999))
				.andExpect(jsonPath("$.data[0].limits.placeBroadcastMax").value(999999999))
				.andExpect(jsonPath("$.data[0].permissionsGranted").isArray());
	}

	@Test
	void plans_paidPlanShape() throws Exception {
		mockMvc.perform(get(PLANS_URL))
				.andExpect(jsonPath("$.data[1].planId").value("woleh_paid_monthly"))
				.andExpect(jsonPath("$.data[1].displayName").value("Woleh Pro"))
				.andExpect(jsonPath("$.data[1].price.amountMinor").value(100))
				.andExpect(jsonPath("$.data[1].price.currency").value("GHS"))
				.andExpect(jsonPath("$.data[1].permissionsGranted[?(@ == 'woleh.place.broadcast')]").exists());
	}

	@Test
	void plans_inactivePlanExcluded() throws Exception {
		planRepository.save(new Plan(
				"woleh_legacy", "Legacy",
				List.of("woleh.place.watch"), 499, "GHS", 10, 0, false));

		mockMvc.perform(get(PLANS_URL))
				.andExpect(jsonPath("$.data.length()").value(2));
	}
}
