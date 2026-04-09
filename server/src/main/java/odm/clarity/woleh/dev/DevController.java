package odm.clarity.woleh.dev;

import java.net.URI;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.model.PaymentSession;
import odm.clarity.woleh.repository.PaymentSessionRepository;
import odm.clarity.woleh.subscription.SubscriptionService;

import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Development-only endpoints for manual and automated testing.
 *
 * <p>Excluded from {@code prod} to ensure no payment shortcuts exist in production.
 * All endpoints are unauthenticated; the session ID acts as a one-time token.
 */
@RestController
@RequestMapping("/api/v1/dev")
@Profile("!prod")
public class DevController {

	private final PaymentSessionRepository paymentSessionRepository;
	private final SubscriptionService subscriptionService;

	public DevController(
			PaymentSessionRepository paymentSessionRepository,
			SubscriptionService subscriptionService) {
		this.paymentSessionRepository = paymentSessionRepository;
		this.subscriptionService = subscriptionService;
	}

	/**
	 * Simulates a payment-provider hosted checkout page (API_CONTRACT.md §6.6, ADR 0005).
	 *
	 * <p>Without {@code result}: renders an HTML page with "Simulate success" and
	 * "Simulate failure" links so developers can trigger either outcome manually from a browser
	 * or Flutter's WebView.
	 *
	 * <p>With {@code result=success|failure}: processes the payment outcome and responds with a
	 * 302 redirect to the app deep link ({@code woleh://subscription/result?status=...&sessionId=...})
	 * which Flutter's WebView can intercept via its navigation-delegate.
	 */
	@GetMapping("/checkout-stub")
	ResponseEntity<?> checkoutStub(
			@RequestParam String sessionId,
			@RequestParam(required = false) String result) {

		PaymentSession session = paymentSessionRepository.findBySessionId(sessionId).orElse(null);
		if (session == null) {
			return ResponseEntity.badRequest()
					.contentType(MediaType.APPLICATION_JSON)
					.body(ApiEnvelope.error("Unknown session: " + sessionId, "NOT_FOUND"));
		}

		// No result param → render the manual-simulation HTML page
		if (result == null) {
			return ResponseEntity.ok()
					.contentType(MediaType.TEXT_HTML)
					.body(buildHtmlPage(sessionId));
		}

		boolean isSuccess = "success".equalsIgnoreCase(result);
		if (!isSuccess && !"failure".equalsIgnoreCase(result)) {
			return ResponseEntity.badRequest()
					.contentType(MediaType.APPLICATION_JSON)
					.body(ApiEnvelope.error(
							"Invalid result value '" + result + "': must be 'success' or 'failure'",
							"BAD_REQUEST"));
		}

		subscriptionService.confirmPayment(session.getProviderReference(), isSuccess);

		String deepLink = "woleh://subscription/result?status=" + result.toLowerCase()
				+ "&sessionId=" + sessionId;
		return ResponseEntity.status(HttpStatus.FOUND)
				.location(URI.create(deepLink))
				.build();
	}

	private String buildHtmlPage(String sessionId) {
		return """
				<!DOCTYPE html>
				<html lang="en">
				<head>
				  <meta charset="UTF-8">
				  <meta name="viewport" content="width=device-width,initial-scale=1">
				  <title>Dev Checkout Stub</title>
				  <style>
				    body{font-family:sans-serif;max-width:480px;margin:60px auto;padding:20px}
				    h2{margin-bottom:.5rem}
				    code{background:#f1f5f9;padding:2px 6px;border-radius:4px;font-size:.9rem}
				    .btn{display:inline-block;padding:12px 24px;margin:8px 8px 0 0;border-radius:8px;
				         text-decoration:none;font-size:1rem;font-weight:600;color:#fff}
				    .ok{background:#22c55e}.fail{background:#ef4444}
				  </style>
				</head>
				<body>
				  <h2>Dev Payment Stub</h2>
				  <p>Session: <code>%s</code></p>
				  <p>Simulate the payment outcome:</p>
				  <a class="btn ok"   href="/api/v1/dev/checkout-stub?sessionId=%s&result=success">✓ Simulate success</a>
				  <a class="btn fail" href="/api/v1/dev/checkout-stub?sessionId=%s&result=failure">✗ Simulate failure</a>
				</body>
				</html>
				""".formatted(sessionId, sessionId, sessionId);
	}
}
