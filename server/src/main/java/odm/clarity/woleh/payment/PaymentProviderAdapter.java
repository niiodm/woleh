package odm.clarity.woleh.payment;

/**
 * Provider-agnostic contract for payment operations.
 *
 * <p>Implementations are profile-scoped: {@link StubPaymentProviderAdapter} is active on
 * all non-production profiles; a real Ghana-local provider implementation is plugged in
 * for {@code prod} by supplying an {@code @Profile("prod")} bean (ADR 0005).
 */
public interface PaymentProviderAdapter {

	/**
	 * Creates a hosted checkout session with the payment provider.
	 *
	 * @param userId         our internal user identifier (for provider metadata)
	 * @param planId         our internal plan identifier (for provider metadata)
	 * @param amountMinor    charge amount in the smallest currency unit (e.g. pesewas for GHS)
	 * @param currency       ISO-4217 currency code (e.g. {@code "GHS"})
	 * @param returnUrl      deep link the provider should redirect to after payment
	 *                       (e.g. {@code woleh://subscription/result})
	 * @param webhookRef     our internal session reference echoed back in webhooks;
	 *                       used to look up the {@code PaymentSession} on confirmation
	 * @return {@link CheckoutSession} containing the URL to open in the WebView
	 */
	CheckoutSession createCheckoutSession(
			String userId,
			String planId,
			long amountMinor,
			String currency,
			String returnUrl,
			String webhookRef);

	/**
	 * Verifies the provider's webhook signature to guard against forged callbacks.
	 * Returns {@code true} when the signature is valid; {@code false} to reject the call.
	 *
	 * @param rawBody        the raw (un-parsed) request body bytes as a string
	 * @param providerHeader the signature or HMAC header value sent by the provider
	 */
	boolean verifyWebhookSignature(String rawBody, String providerHeader);

	/**
	 * Parses the verified webhook body into a normalised {@link WebhookEvent}.
	 * Implementations translate the provider's event vocabulary to
	 * {@code "payment_success"} or {@code "payment_failed"}.
	 */
	WebhookEvent parseWebhookEvent(String rawBody);
}
