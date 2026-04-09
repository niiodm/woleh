package odm.clarity.woleh.subscription;

import java.util.List;

import jakarta.validation.Valid;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.subscription.dto.CheckoutRequest;
import odm.clarity.woleh.subscription.dto.CheckoutResponse;
import odm.clarity.woleh.subscription.dto.PlanResponse;
import odm.clarity.woleh.subscription.dto.SubscriptionStatusResponse;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Subscription endpoints (API_CONTRACT.md §6.5–§6.7). */
@RestController
@RequestMapping("/api/v1/subscription")
public class SubscriptionController {

	private final PlanService planService;
	private final SubscriptionService subscriptionService;
	private final EntitlementService entitlementService;

	public SubscriptionController(
			PlanService planService,
			SubscriptionService subscriptionService,
			EntitlementService entitlementService) {
		this.planService = planService;
		this.subscriptionService = subscriptionService;
		this.entitlementService = entitlementService;
	}

	/** GET /api/v1/subscription/plans — public plan catalog (API_CONTRACT.md §6.5). */
	@GetMapping("/plans")
	ResponseEntity<ApiEnvelope<List<PlanResponse>>> plans() {
		return ResponseEntity.ok(ApiEnvelope.success("OK", planService.listActivePlans()));
	}

	/** POST /api/v1/subscription/checkout — initiate a paid checkout (API_CONTRACT.md §6.6). */
	@PostMapping("/checkout")
	ResponseEntity<ApiEnvelope<CheckoutResponse>> checkout(
			@AuthenticationPrincipal Long userId,
			@RequestBody @Valid CheckoutRequest request) {
		CheckoutResponse response = subscriptionService.initiateCheckout(userId, request.planId());
		return ResponseEntity.ok(ApiEnvelope.success("Checkout session created", response));
	}

	/** GET /api/v1/subscription/status — detailed subscription state (API_CONTRACT.md §5). */
	@GetMapping("/status")
	ResponseEntity<ApiEnvelope<SubscriptionStatusResponse>> status(
			@AuthenticationPrincipal Long userId) {
		Entitlements e = entitlementService.computeEntitlements(userId);
		SubscriptionStatusResponse response = new SubscriptionStatusResponse(
				e.permissions(),
				e.tier(),
				new SubscriptionStatusResponse.Limits(e.placeWatchMax(), e.placeBroadcastMax()),
				new SubscriptionStatusResponse.Subscription(
						e.subscriptionStatus(), e.currentPeriodEnd(), e.inGracePeriod()));
		return ResponseEntity.ok(ApiEnvelope.success("OK", response));
	}
}
