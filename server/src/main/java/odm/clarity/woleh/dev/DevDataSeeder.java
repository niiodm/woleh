package odm.clarity.woleh.dev;

import java.util.List;

import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.repository.PlanRepository;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Seeds the plan catalog in the {@code dev} profile (H2 in-memory).
 *
 * <p>Flyway is disabled in dev because the schema is owned by {@code ddl-auto: create-drop}.
 * This runner fills the gap by inserting the same seed rows that {@code V4__seed_plans.sql}
 * provides in production. The {@code planRepository.count() == 0} guard makes it idempotent
 * so re-running the application against a persistent H2 URL won't duplicate rows.
 *
 * <p>Not active in tests — tests use their own {@code @BeforeEach} setup.
 */
@Component
@Profile("dev")
public class DevDataSeeder implements ApplicationRunner {

	private static final Logger log = LoggerFactory.getLogger(DevDataSeeder.class);

	private final PlanRepository planRepository;

	public DevDataSeeder(PlanRepository planRepository) {
		this.planRepository = planRepository;
	}

	@Override
	@Transactional
	public void run(ApplicationArguments args) {
		if (planRepository.count() > 0) {
			return;
		}

		planRepository.saveAll(List.of(
				new Plan(
						"woleh_free", "Free",
						List.of("woleh.account.profile", "woleh.plans.read",
								"woleh.place.watch", "woleh.place.broadcast"),
						0, "GHS", 999_999_999, 999_999_999, true),
				new Plan(
						"woleh_paid_monthly", "Woleh Pro",
						List.of("woleh.account.profile", "woleh.plans.read",
								"woleh.place.watch", "woleh.place.broadcast"),
						100, "GHS", 999_999_999, 999_999_999, true)));

		log.info("[DEV] Seeded 2 plans: woleh_free, woleh_paid_monthly");
	}
}
