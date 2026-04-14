package odm.clarity.woleh.subscription;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Optional;

import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.repository.PlanRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

import jakarta.persistence.EntityManager;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class PlanRepositoryTest {

	@Autowired
	PlanRepository planRepository;

	@Autowired
	EntityManager entityManager;

	@BeforeEach
	void setup() {
		planRepository.deleteAll();
	}

	@Test
	void findByPlanId_returnsCorrectPlan() {
		planRepository.save(new Plan(
				"woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.account.profile", "woleh.plans.read", "woleh.place.watch", "woleh.place.broadcast"),
				100, "GHS", 999999999, 999999999, 20, true));

		Optional<Plan> found = planRepository.findByPlanId("woleh_paid_monthly");

		assertThat(found).isPresent();
		assertThat(found.get().getDisplayName()).isEqualTo("Woleh Pro");
		assertThat(found.get().getPriceAmountMinor()).isEqualTo(100);
		assertThat(found.get().getPriceCurrency()).isEqualTo("GHS");
		assertThat(found.get().getPlaceWatchMax()).isEqualTo(999999999);
		assertThat(found.get().getPlaceBroadcastMax()).isEqualTo(999999999);
		assertThat(found.get().getSavedPlaceListMax()).isEqualTo(20);
		assertThat(found.get().isActive()).isTrue();
	}

	@Test
	void findByPlanId_permissionsRoundTripThroughConverter() {
		List<String> perms = List.of(
				"woleh.account.profile", "woleh.plans.read",
				"woleh.place.watch", "woleh.place.broadcast");

		planRepository.save(new Plan("woleh_paid_monthly", "Woleh Pro", perms, 999, "GHS", 50, 50, 20, true));

		// Flush to DB and evict from the first-level cache to force a real DB read.
		entityManager.flush();
		entityManager.clear();

		Optional<Plan> found = planRepository.findByPlanId("woleh_paid_monthly");

		assertThat(found).isPresent();
		assertThat(found.get().getPermissionsGranted()).containsExactlyElementsOf(perms);
	}

	@Test
	void findByPlanId_unknownId_returnsEmpty() {
		assertThat(planRepository.findByPlanId("does_not_exist")).isEmpty();
	}

	@Test
	void findByActiveTrueOrderByPriceAmountMinorAsc_returnsFreeFirst() {
		planRepository.save(new Plan("woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.place.broadcast"), 100, "GHS", 999999999, 999999999, 20, true));
		planRepository.save(new Plan("woleh_free", "Free",
				List.of("woleh.place.watch"), 0, "GHS", 999999999, 999999999, 20, true));

		entityManager.flush();
		entityManager.clear();

		List<Plan> plans = planRepository.findByActiveTrueOrderByPriceAmountMinorAsc();

		assertThat(plans).hasSize(2);
		assertThat(plans.get(0).getPlanId()).isEqualTo("woleh_free");
		assertThat(plans.get(1).getPlanId()).isEqualTo("woleh_paid_monthly");
	}

	@Test
	void findByActiveTrueOrderByPriceAmountMinorAsc_excludesInactivePlans() {
		planRepository.save(new Plan("woleh_paid_monthly", "Woleh Pro",
				List.of("woleh.place.broadcast"), 100, "GHS", 999999999, 999999999, 20, true));
		planRepository.save(new Plan("woleh_legacy", "Legacy",
				List.of("woleh.place.watch"), 499, "GHS", 10, 0, 20, false));

		entityManager.flush();
		entityManager.clear();

		List<Plan> plans = planRepository.findByActiveTrueOrderByPriceAmountMinorAsc();

		assertThat(plans).hasSize(1);
		assertThat(plans.get(0).getPlanId()).isEqualTo("woleh_paid_monthly");
	}
}
