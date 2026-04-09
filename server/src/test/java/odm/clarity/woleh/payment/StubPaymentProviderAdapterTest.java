package odm.clarity.woleh.payment;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;

import odm.clarity.woleh.config.PaymentProviderProperties;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class StubPaymentProviderAdapterTest {

	private static final String BASE_URL = "http://localhost:8080";
	private static final String SESSION_REF = "woleh_psess_test_001";

	private StubPaymentProviderAdapter adapter;

	@BeforeEach
	void setUp() {
		adapter = new StubPaymentProviderAdapter(new PaymentProviderProperties(BASE_URL));
	}

	// ── createCheckoutSession ─────────────────────────────────────────────────

	@Test
	void createCheckoutSession_urlContainsBaseUrlAndSessionId() {
		CheckoutSession session = checkout();

		assertThat(session.checkoutUrl())
				.startsWith(BASE_URL + "/api/v1/dev/checkout-stub")
				.contains("sessionId=" + SESSION_REF);
	}

	@Test
	void createCheckoutSession_providerReferenceMatchesWebhookRef() {
		CheckoutSession session = checkout();

		assertThat(session.providerReference()).isEqualTo(SESSION_REF);
	}

	@Test
	void createCheckoutSession_expiresAtIsInFuture() {
		CheckoutSession session = checkout();

		assertThat(session.expiresAt()).isAfter(Instant.now());
	}

	// ── verifyWebhookSignature ────────────────────────────────────────────────

	@Test
	void verifyWebhookSignature_alwaysReturnsTrue() {
		assertThat(adapter.verifyWebhookSignature("{}", "any-header")).isTrue();
		assertThat(adapter.verifyWebhookSignature("{}", null)).isTrue();
		assertThat(adapter.verifyWebhookSignature("{}", "")).isTrue();
	}

	// ── parseWebhookEvent ─────────────────────────────────────────────────────

	@Test
	void parseWebhookEvent_successEvent() {
		String body = """
				{"type":"payment_success","providerReference":"ref-abc"}
				""";

		WebhookEvent event = adapter.parseWebhookEvent(body);

		assertThat(event.type()).isEqualTo("payment_success");
		assertThat(event.providerReference()).isEqualTo("ref-abc");
		assertThat(event.isSuccess()).isTrue();
	}

	@Test
	void parseWebhookEvent_failureEvent() {
		String body = """
				{"type":"payment_failed","providerReference":"ref-xyz"}
				""";

		WebhookEvent event = adapter.parseWebhookEvent(body);

		assertThat(event.type()).isEqualTo("payment_failed");
		assertThat(event.isSuccess()).isFalse();
	}

	@Test
	void parseWebhookEvent_malformedJson_treatedAsFailure() {
		WebhookEvent event = adapter.parseWebhookEvent("not-valid-json");

		assertThat(event.isSuccess()).isFalse();
	}

	// ── helpers ──────────────────────────────────────────────────────────────

	private CheckoutSession checkout() {
		return adapter.createCheckoutSession(
				"1", "woleh_paid_monthly", 100L, "GHS",
				"woleh://subscription/result", SESSION_REF);
	}
}
