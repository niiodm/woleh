package odm.clarity.woleh.ws;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;
import static org.springframework.http.HttpMethod.PUT;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.TimeUnit;

import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.UserPlaceListRepository;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.security.JwtService;
import odm.clarity.woleh.subscription.EntitlementService;
import odm.clarity.woleh.subscription.Entitlements;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

/**
 * End-to-end integration tests for real-time match dispatch over WebSocket.
 *
 * <p>Scenario A — broadcast PUT triggers watcher notification:
 * <ol>
 *   <li>Watcher sets a watch list and connects to WS.
 *   <li>Broadcaster sets a broadcast list whose normalized names intersect the watch list.
 *   <li>Assert the watcher's WS session receives a {@code match} event with the correct
 *       {@code matchedNames} and {@code counterpartyUserId}.
 * </ol>
 *
 * <p>Scenario B — watch PUT triggers broadcaster notification:
 * <ol>
 *   <li>Broadcaster sets a broadcast list and connects to WS.
 *   <li>Watcher sets a watch list whose normalized names intersect the broadcast list.
 *   <li>Assert the broadcaster's WS session receives a {@code match} event.
 * </ol>
 *
 * <p>Uses {@code RANDOM_PORT}, {@link TestRestTemplate} for REST calls, and the Java 11
 * {@code java.net.http.HttpClient} WebSocket API. {@link EntitlementService} is mocked so
 * no subscription database setup is required.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class MatchDispatchIntegrationTest {

	private static final String WATCH_URL = "/api/v1/me/places/watch";
	private static final String BROADCAST_URL = "/api/v1/me/places/broadcast";

	private static final Entitlements WATCH_ONLY = new Entitlements(
			List.of("woleh.account.profile", "woleh.plans.read", "woleh.place.watch"),
			"free", 5, 0, 10, "none", null, false);

	private static final Entitlements BROADCAST_AND_WATCH = new Entitlements(
			List.of("woleh.account.profile", "woleh.plans.read",
					"woleh.place.watch", "woleh.place.broadcast"),
			"paid", 50, 50, 20, "active", Instant.now().plus(30, ChronoUnit.DAYS).toString(), false);

	@LocalServerPort
	private int port;

	@Autowired
	private UserRepository userRepository;

	@Autowired
	private UserPlaceListRepository placeListRepository;

	@Autowired
	private JwtService jwtService;

	@Autowired
	private TestRestTemplate restTemplate;

	@MockBean
	private EntitlementService entitlementService;

	private User watcher;
	private User broadcaster;
	private String watcherToken;
	private String broadcasterToken;

	@BeforeEach
	void setUp() {
		placeListRepository.deleteAll();
		userRepository.deleteAll();

		watcher = userRepository.save(new User("+233241880001"));
		broadcaster = userRepository.save(new User("+233241880002"));

		watcherToken = jwtService.createAccessToken(watcher.getId(), Instant.now());
		broadcasterToken = jwtService.createAccessToken(broadcaster.getId(), Instant.now());

		when(entitlementService.computeEntitlements(watcher.getId())).thenReturn(WATCH_ONLY);
		when(entitlementService.computeEntitlements(broadcaster.getId())).thenReturn(BROADCAST_AND_WATCH);
	}

	@AfterEach
	void tearDown() {
		placeListRepository.deleteAll();
		userRepository.deleteAll();
	}

	// ── scenario A ─────────────────────────────────────────────────────────────

	@Test
	void broadcastPut_notifiesConnectedWatcher() throws Exception {
		// Watcher saves a watch list.
		assertPutOk(WATCH_URL, watcherToken, "[\"Madina\",\"Lapaz\"]");

		// Watcher connects to WS.
		CompletableFuture<String> firstMatchFuture = new CompletableFuture<>();
		WebSocket ws = connectWs(watcherToken, firstMatchFuture);
		try {
			// Broadcaster saves a broadcast list that overlaps ("MADINA" → "madina").
			assertPutOk(BROADCAST_URL, broadcasterToken, "[\"MADINA\",\"Kaneshie\"]");

			// Watcher's WS session should receive a match event.
			String message = firstMatchFuture.get(5, TimeUnit.SECONDS);

			assertThat(message).contains("\"match\"");
			assertThat(message).contains("\"madina\"");
			assertThat(message).contains(String.valueOf(broadcaster.getId()));
		}
		finally {
			closeQuietly(ws);
		}
	}

	// ── scenario B ─────────────────────────────────────────────────────────────

	@Test
	void watchPut_notifiesConnectedBroadcaster() throws Exception {
		// Broadcaster saves a broadcast list.
		assertPutOk(BROADCAST_URL, broadcasterToken, "[\"Kaneshie\",\"Madina\"]");

		// Broadcaster connects to WS.
		CompletableFuture<String> firstMatchFuture = new CompletableFuture<>();
		WebSocket ws = connectWs(broadcasterToken, firstMatchFuture);
		try {
			// Watcher saves a watch list that overlaps ("MADINA" → "madina").
			assertPutOk(WATCH_URL, watcherToken, "[\"MADINA\",\"Lapaz\"]");

			// Broadcaster's WS session should receive a match event.
			String message = firstMatchFuture.get(5, TimeUnit.SECONDS);

			assertThat(message).contains("\"match\"");
			assertThat(message).contains("\"madina\"");
			assertThat(message).contains(String.valueOf(watcher.getId()));
		}
		finally {
			closeQuietly(ws);
		}
	}

	// ── helpers ────────────────────────────────────────────────────────────────

	/** PUT the place list and assert the server returned 200 OK. */
	private void assertPutOk(String path, String token, String namesJson) {
		HttpHeaders headers = new HttpHeaders();
		headers.setContentType(MediaType.APPLICATION_JSON);
		headers.set(HttpHeaders.AUTHORIZATION, "Bearer " + token);
		ResponseEntity<String> resp = restTemplate.exchange(
				path, PUT, new HttpEntity<>("{\"names\":" + namesJson + "}", headers), String.class);
		assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
	}

	/**
	 * Opens a WebSocket connection authenticated with {@code token}. The supplied
	 * {@link CompletableFuture} is completed when the first non-heartbeat message arrives.
	 */
	private WebSocket connectWs(String token, CompletableFuture<String> firstNonHeartbeat)
			throws Exception {
		URI uri = URI.create("ws://localhost:" + port + "/ws/v1/transit?access_token=" + token);
		return HttpClient.newHttpClient()
				.newWebSocketBuilder()
				.buildAsync(uri, matchListener(firstNonHeartbeat))
				.get(5, TimeUnit.SECONDS);
	}

	/**
	 * Returns a {@link WebSocket.Listener} that completes {@code target} with the first
	 * non-heartbeat text message received.
	 */
	private static WebSocket.Listener matchListener(CompletableFuture<String> target) {
		return new WebSocket.Listener() {

			private final StringBuilder buffer = new StringBuilder();

			@Override
			public void onOpen(WebSocket ws) {
				ws.request(1); // begin receiving messages
			}

			@Override
			public CompletionStage<?> onText(WebSocket ws, CharSequence data, boolean last) {
				buffer.append(data);
				if (last) {
					String msg = buffer.toString();
					buffer.setLength(0);
					if (msg.contains("\"heartbeat\"")) {
						ws.request(1); // discard and wait for next
					}
					else {
						target.complete(msg); // done — no need to request more
					}
				}
				else {
					ws.request(1); // partial frame; request the rest
				}
				return null;
			}

			@Override
			public CompletionStage<?> onClose(WebSocket ws, int statusCode, String reason) {
				target.completeExceptionally(
						new RuntimeException("WS closed before match event: " + statusCode));
				return null;
			}

			@Override
			public void onError(WebSocket ws, Throwable error) {
				target.completeExceptionally(error);
			}
		};
	}

	private static void closeQuietly(WebSocket ws) {
		try {
			ws.sendClose(WebSocket.NORMAL_CLOSURE, "done").get(3, TimeUnit.SECONDS);
		}
		catch (Exception ignored) {
		}
	}
}
