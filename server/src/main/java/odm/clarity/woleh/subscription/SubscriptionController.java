package odm.clarity.woleh.subscription;

import java.util.List;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.subscription.dto.PlanResponse;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Subscription endpoints (API_CONTRACT.md §6.5–§6.6).
 * Further handlers (checkout, status, webhook) are added in subsequent Phase 1 steps.
 */
@RestController
@RequestMapping("/api/v1/subscription")
public class SubscriptionController {

	private final PlanService planService;

	public SubscriptionController(PlanService planService) {
		this.planService = planService;
	}

	/** GET /api/v1/subscription/plans — public plan catalog (API_CONTRACT.md §6.5). */
	@GetMapping("/plans")
	ResponseEntity<ApiEnvelope<List<PlanResponse>>> plans() {
		return ResponseEntity.ok(ApiEnvelope.success("OK", planService.listActivePlans()));
	}
}
