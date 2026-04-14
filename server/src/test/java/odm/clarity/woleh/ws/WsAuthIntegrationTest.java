package odm.clarity.woleh.ws;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.net.http.WebSocketHandshakeException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;

import odm.clarity.woleh.security.JwtService;
import odm.clarity.woleh.subscription.EntitlementService;
import odm.clarity.woleh.subscription.Entitlements;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.boot.test.web.server.LocalServerPort;

/**
 * Integration tests for WebSocket authentication at {@code /ws/v1/transit}.
 *
 * <p>Uses a real embedded server ({@code RANDOM_PORT}) and the Java 11
 * {@code java.net.http.HttpClient} WebSocket API. {@link EntitlementService} is mocked
 * so no subscription database setup is required.
 *
 * <p>Test matrix:
 * <ul>
 *   <li>Valid token (free tier with {@code woleh.place.watch}) → 101 Switching Protocols
 *   <li>Missing {@code access_token} query param → 403
 *   <li>Garbage / invalid token → 403
 *   <li>Valid token but user has no place permission → 403
 * </ul>
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class WsAuthIntegrationTest {

	private static final long TEST_USER_ID = 999L;

	private static final Entitlements FREE_TIER = new Entitlements(
			List.of("woleh.account.profile", "woleh.plans.read", "woleh.place.watch"),
			"free", 5, 0, 10, "none", null, false);

	private static final Entitlements NO_PLACE_PERMS = new Entitlements(
			List.of("woleh.account.profile", "woleh.plans.read"),
			"free", 0, 0, 10, "none", null, false);

	@LocalServerPort
	private int port;

	@Autowired
	private JwtService jwtService;

	@MockBean
	private EntitlementService entitlementService;

	private String validToken;

	@BeforeEach
	void setUp() {
		validToken = jwtService.createAccessToken(TEST_USER_ID, Instant.now());
		when(entitlementService.computeEntitlements(TEST_USER_ID)).thenReturn(FREE_TIER);
	}

	@Test
	void validToken_upgradeSucceeds() throws Exception {
		CompletableFuture<WebSocket> future = wsBuilder()
				.buildAsync(wsUri("?access_token=" + validToken), noopListener());

		WebSocket ws = future.get(5, TimeUnit.SECONDS);
		assertThat(ws).isNotNull();
		ws.sendClose(WebSocket.NORMAL_CLOSURE, "done").join();
	}

	@Test
	void missingToken_rejected() {
		CompletableFuture<WebSocket> future = wsBuilder()
				.buildAsync(wsUri(""), noopListener());

		assertRejectedWith403(future);
	}

	@Test
	void invalidToken_rejected() {
		CompletableFuture<WebSocket> future = wsBuilder()
				.buildAsync(wsUri("?access_token=not.a.jwt"), noopListener());

		assertRejectedWith403(future);
	}

	@Test
	void expiredToken_rejected() {
		String expiredToken = jwtService.createAccessToken(TEST_USER_ID, Instant.now().minus(365, ChronoUnit.DAYS));

		CompletableFuture<WebSocket> future = wsBuilder()
				.buildAsync(wsUri("?access_token=" + expiredToken), noopListener());

		assertRejectedWith403(future);
	}

	@Test
	void noPlacePermission_rejected() {
		when(entitlementService.computeEntitlements(TEST_USER_ID)).thenReturn(NO_PLACE_PERMS);

		CompletableFuture<WebSocket> future = wsBuilder()
				.buildAsync(wsUri("?access_token=" + validToken), noopListener());

		assertRejectedWith403(future);
	}

	// ── helpers ───────────────────────────────────────────────────────────────────

	private WebSocket.Builder wsBuilder() {
		return HttpClient.newHttpClient().newWebSocketBuilder();
	}

	private URI wsUri(String queryAndFragment) {
		return URI.create("ws://localhost:" + port + "/ws/v1/transit" + queryAndFragment);
	}

	private static WebSocket.Listener noopListener() {
		return new WebSocket.Listener() {
		};
	}

	private static void assertRejectedWith403(CompletableFuture<WebSocket> future) {
		assertThatThrownBy(() -> future.get(5, TimeUnit.SECONDS))
				.isInstanceOf(ExecutionException.class)
				.satisfies(t -> {
					Throwable cause = ((ExecutionException) t).getCause();
					assertThat(cause).isInstanceOf(WebSocketHandshakeException.class);
					int status = ((WebSocketHandshakeException) cause).getResponse().statusCode();
					assertThat(status).isEqualTo(403);
				});
	}
}
