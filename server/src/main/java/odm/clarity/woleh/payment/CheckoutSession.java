package odm.clarity.woleh.payment;

import java.time.Instant;

/**
 * Result of {@link PaymentProviderAdapter#createCheckoutSession}.
 * The {@code checkoutUrl} is opened in the client's WebView (ADR 0005).
 */
public record CheckoutSession(
		String checkoutUrl,
		String providerReference,
		Instant expiresAt) {
}
