package odm.clarity.woleh.payment;

import java.time.Instant;
import java.time.temporal.ChronoUnit;

import odm.clarity.woleh.config.PaymentProviderProperties;

import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Dev/test payment provider adapter that simulates a hosted checkout without a real
 * payment gateway.
 *
 * <p>The returned {@code checkoutUrl} points at the local dev stub endpoint
 * ({@code GET /api/v1/dev/checkout-stub?sessionId=...}) which renders two links —
 * "Simulate success" and "Simulate failure" — that trigger the appropriate server-side
 * confirmation and redirect back to the app deep link (implemented in step 2.8).
 *
 * <p>Active on all profiles except {@code prod}; swap with a real implementation
 * annotated {@code @Profile("prod")} when integrating a Ghana-local provider (ADR 0005).
 */
@Component
@Profile("!prod")
public class StubPaymentProviderAdapter implements PaymentProviderAdapter {

	private static final ObjectMapper MAPPER = new ObjectMapper();
	private static final int CHECKOUT_EXPIRY_MINUTES = 30;

	private final PaymentProviderProperties properties;

	public StubPaymentProviderAdapter(PaymentProviderProperties properties) {
		this.properties = properties;
	}

	@Override
	public CheckoutSession createCheckoutSession(
			String userId, String planId,
			long amountMinor, String currency,
			String returnUrl, String webhookRef) {

		String checkoutUrl = properties.baseUrl()
				+ "/api/v1/dev/checkout-stub?sessionId=" + webhookRef;

		return new CheckoutSession(
				checkoutUrl,
				webhookRef,
				Instant.now().plus(CHECKOUT_EXPIRY_MINUTES, ChronoUnit.MINUTES));
	}

	/** Stub always accepts — no real signature to verify. */
	@Override
	public boolean verifyWebhookSignature(String rawBody, String providerHeader) {
		return true;
	}

	/**
	 * Parses a simple JSON body: {@code {"type":"payment_success","providerReference":"xxx"}}.
	 * This format is used when the stub webhook is called programmatically in tests.
	 */
	@Override
	public WebhookEvent parseWebhookEvent(String rawBody) {
		try {
			JsonNode node = MAPPER.readTree(rawBody);
			String type = node.path("type").asText("payment_failed");
			String ref = node.path("providerReference").asText("");
			return new WebhookEvent(type, ref);
		} catch (JsonProcessingException e) {
			return new WebhookEvent("payment_failed", "");
		}
	}
}
