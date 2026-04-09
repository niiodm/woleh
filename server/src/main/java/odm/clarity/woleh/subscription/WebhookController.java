package odm.clarity.woleh.subscription;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.payment.PaymentProviderAdapter;
import odm.clarity.woleh.payment.WebhookEvent;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Receives payment provider webhooks (API_CONTRACT.md §6.6, ADR 0005).
 *
 * <p>Authentication is by provider signature ({@code X-Payment-Signature}) rather than JWT;
 * this endpoint is permitted without a Bearer token in {@link odm.clarity.woleh.config.SecurityConfig}.
 */
@RestController
@RequestMapping("/api/v1/webhooks")
public class WebhookController {

	private final PaymentProviderAdapter paymentProviderAdapter;
	private final SubscriptionService subscriptionService;

	public WebhookController(
			PaymentProviderAdapter paymentProviderAdapter,
			SubscriptionService subscriptionService) {
		this.paymentProviderAdapter = paymentProviderAdapter;
		this.subscriptionService = subscriptionService;
	}

	/** POST /api/v1/webhooks/payment — payment outcome from the provider. */
	@PostMapping("/payment")
	ResponseEntity<ApiEnvelope<Void>> payment(
			@RequestBody String rawBody,
			@RequestHeader(value = "X-Payment-Signature", required = false, defaultValue = "") String signature) {

		if (!paymentProviderAdapter.verifyWebhookSignature(rawBody, signature)) {
			return ResponseEntity.status(HttpStatus.BAD_REQUEST)
					.body(ApiEnvelope.error("Invalid webhook signature", "INVALID_SIGNATURE"));
		}

		WebhookEvent event = paymentProviderAdapter.parseWebhookEvent(rawBody);
		subscriptionService.confirmPayment(event.providerReference(), event.isSuccess());

		// Always return 200 for valid-signature calls so the provider does not retry.
		return ResponseEntity.ok(ApiEnvelope.success("Webhook processed", null));
	}
}
