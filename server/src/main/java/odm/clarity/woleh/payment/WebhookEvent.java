package odm.clarity.woleh.payment;

/**
 * Parsed body of a payment provider webhook call.
 * The {@code type} is normalised to {@code "payment_success"} or {@code "payment_failed"}
 * regardless of the provider's own event vocabulary.
 */
public record WebhookEvent(
		String type,
		String providerReference) {

	public boolean isSuccess() {
		return "payment_success".equals(type);
	}
}
