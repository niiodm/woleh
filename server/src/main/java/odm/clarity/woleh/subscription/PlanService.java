package odm.clarity.woleh.subscription;

import java.util.List;

import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.repository.PlanRepository;
import odm.clarity.woleh.subscription.dto.PlanResponse;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(readOnly = true)
public class PlanService {

	private final PlanRepository planRepository;

	public PlanService(PlanRepository planRepository) {
		this.planRepository = planRepository;
	}

	/** Returns all active plans ordered by price ascending (free plan first). */
	public List<PlanResponse> listActivePlans() {
		return planRepository.findByActiveTrueOrderByPriceAmountMinorAsc()
				.stream()
				.map(PlanService::toResponse)
				.toList();
	}

	private static PlanResponse toResponse(Plan plan) {
		return new PlanResponse(
				plan.getPlanId(),
				plan.getDisplayName(),
				plan.getPermissionsGranted(),
				new PlanResponse.Limits(plan.getPlaceWatchMax(), plan.getPlaceBroadcastMax()),
				new PlanResponse.Price(plan.getPriceAmountMinor(), plan.getPriceCurrency()));
	}
}
