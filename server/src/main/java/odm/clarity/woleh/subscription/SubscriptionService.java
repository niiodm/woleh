package odm.clarity.woleh.subscription;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import odm.clarity.woleh.common.error.PaymentException;
import odm.clarity.woleh.common.error.UserNotFoundException;
import odm.clarity.woleh.model.PaymentSession;
import odm.clarity.woleh.model.PaymentSessionStatus;
import odm.clarity.woleh.model.Plan;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.payment.CheckoutSession;
import odm.clarity.woleh.payment.PaymentProviderAdapter;
import odm.clarity.woleh.repository.PaymentSessionRepository;
import odm.clarity.woleh.repository.PlanRepository;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.subscription.dto.CheckoutResponse;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class SubscriptionService {

	private static final String RETURN_URL = "woleh://subscription/result";

	private final PlanRepository planRepository;
	private final PaymentSessionRepository paymentSessionRepository;
	private final UserRepository userRepository;
	private final PaymentProviderAdapter paymentProviderAdapter;
	private final EntitlementService entitlementService;

	public SubscriptionService(
			PlanRepository planRepository,
			PaymentSessionRepository paymentSessionRepository,
			UserRepository userRepository,
			PaymentProviderAdapter paymentProviderAdapter,
			EntitlementService entitlementService) {
		this.planRepository = planRepository;
		this.paymentSessionRepository = paymentSessionRepository;
		this.userRepository = userRepository;
		this.paymentProviderAdapter = paymentProviderAdapter;
		this.entitlementService = entitlementService;
	}

	/**
	 * Initiates a checkout session for the given user and plan (API_CONTRACT.md §6.6).
	 *
	 * <p>Idempotent: if a non-expired {@code PENDING} session already exists for this
	 * user+plan it is returned as-is rather than creating a duplicate.
	 */
	public CheckoutResponse initiateCheckout(Long userId, String planId) {
		// Permission guard — woleh.plans.read is required to start a checkout.
		if (!entitlementService.computeEntitlements(userId).permissions().contains("woleh.plans.read")) {
			throw new PaymentException("Checkout requires the woleh.plans.read permission",
					HttpStatus.FORBIDDEN.value());
		}

		// Validate plan
		Plan plan = planRepository.findByPlanId(planId)
				.orElseThrow(() -> new PaymentException("Unknown plan: " + planId,
						HttpStatus.BAD_REQUEST.value()));
		if (!plan.isActive()) {
			throw new PaymentException("Plan is not available: " + planId,
					HttpStatus.BAD_REQUEST.value());
		}
		if (plan.getPriceAmountMinor() == 0) {
			throw new PaymentException("The free plan does not require a checkout",
					HttpStatus.BAD_REQUEST.value());
		}

		// Idempotency: return an existing un-expired pending session
		Optional<PaymentSession> existing = paymentSessionRepository
				.findTopByUser_IdAndPlan_PlanIdAndStatusOrderByCreatedAtDesc(
						userId, planId, PaymentSessionStatus.PENDING);
		if (existing.isPresent() && existing.get().getExpiresAt().isAfter(Instant.now())) {
			PaymentSession s = existing.get();
			return new CheckoutResponse(s.getCheckoutUrl(), s.getSessionId(),
					s.getExpiresAt().toString());
		}

		// Load user (needed for the PaymentSession FK)
		User user = userRepository.findById(userId)
				.orElseThrow(() -> new UserNotFoundException(userId));

		// Create checkout session with the provider
		String sessionId = "woleh_psess_" + UUID.randomUUID().toString().replace("-", "");
		CheckoutSession session = paymentProviderAdapter.createCheckoutSession(
				String.valueOf(userId), planId,
				plan.getPriceAmountMinor(), plan.getPriceCurrency(),
				RETURN_URL, sessionId);

		// Persist the payment session
		PaymentSession ps = new PaymentSession(
				user, plan, sessionId, session.checkoutUrl(), session.expiresAt());
		ps.setProviderReference(session.providerReference());
		paymentSessionRepository.save(ps);

		return new CheckoutResponse(session.checkoutUrl(), sessionId, session.expiresAt().toString());
	}
}
