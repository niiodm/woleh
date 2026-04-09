package odm.clarity.woleh.repository;

import java.util.List;
import java.util.Optional;

import odm.clarity.woleh.model.Plan;

import org.springframework.data.jpa.repository.JpaRepository;

public interface PlanRepository extends JpaRepository<Plan, Long> {

	Optional<Plan> findByPlanId(String planId);

	List<Plan> findByActiveTrueOrderByPriceAmountMinorAsc();
}
