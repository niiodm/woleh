package odm.clarity.woleh.subscription.dto;

/** Response body for {@code POST /api/v1/subscription/checkout} (API_CONTRACT.md §6.6). */
public record CheckoutResponse(
		String checkoutUrl,
		String sessionId,
		String expiresAt) {
}
