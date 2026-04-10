package odm.clarity.woleh.ws;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;
import static org.springframework.http.HttpMethod.POST;
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
import odm.clarity.woleh.ratelimit.LocationPublishRateLimiter;
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
 * Match-scoped {@code peer_location} fan-out (MAP_LIVE_LOCATION_PLAN §3.3).
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class PeerLocationDispatchIntegrationTest {

	private static final String WATCH_URL = "/api/v1/me/places/watch";
	private static final String BROADCAST_URL = "/api/v1/me/places/broadcast";
	private static final String LOCATION_URL = "/api/v1/me/location";
	private static final String SHARING_URL = "/api/v1/me/location-sharing";

	private static final Entitlements WATCH_ONLY = new Entitlements(
			List.of("woleh.account.profile", "woleh.plans.read", "woleh.place.watch"),
			"free", 5, 0, "none", null, false);

	private static final Entitlements BROADCAST_AND_WATCH = new Entitlements(
			List.of("woleh.account.profile", "woleh.plans.read",
					"woleh.place.watch", "woleh.place.broadcast"),
			"paid", 50, 50, "active", Instant.now().plus(30, ChronoUnit.DAYS).toString(), false);

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

	@Autowired
	private LocationPublishRateLimiter locationPublishRateLimiter;

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
		locationPublishRateLimiter.clearForTesting();

		watcher = userRepository.save(new User("+233241990001"));
		broadcaster = userRepository.save(new User("+233241990002"));

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

	@Test
	void locationPost_deliversPeerLocationToMatchedWatcher() throws Exception {
		assertPutOk(WATCH_URL, watcherToken, "{\"names\":[\"Madina\",\"Lapaz\"]}");
		assertPutOk(BROADCAST_URL, broadcasterToken, "{\"names\":[\"MADINA\",\"Kaneshie\"]}");

		assertPutOk(SHARING_URL, broadcasterToken, "{\"enabled\":true}");

		CompletableFuture<String> peerLocFuture = new CompletableFuture<>();
		WebSocket ws = connectWs(watcherToken, peerLocFuture);
		try {
			assertPostLocationOk(broadcasterToken, 5.6037, -0.187);

			String message = peerLocFuture.get(5, TimeUnit.SECONDS);
			assertThat(message).contains("\"peer_location\"");
			assertThat(message).contains("\"userId\":\"" + broadcaster.getId() + "\"");
			assertThat(message).contains("\"latitude\":5.6037");
			assertThat(message).contains("\"longitude\":-0.187");
			assertThat(message).contains("\"receivedAt\"");
		}
		finally {
			closeQuietly(ws);
		}
	}

	private void assertPutOk(String path, String token, String body) {
		HttpHeaders headers = new HttpHeaders();
		headers.setContentType(MediaType.APPLICATION_JSON);
		headers.set(HttpHeaders.AUTHORIZATION, "Bearer " + token);
		ResponseEntity<String> resp = restTemplate.exchange(
				path, PUT, new HttpEntity<>(body, headers), String.class);
		assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
	}

	private void assertPostLocationOk(String token, double lat, double lng) {
		HttpHeaders headers = new HttpHeaders();
		headers.setContentType(MediaType.APPLICATION_JSON);
		headers.set(HttpHeaders.AUTHORIZATION, "Bearer " + token);
		String json = "{\"latitude\":" + lat + ",\"longitude\":" + lng + "}";
		ResponseEntity<String> resp = restTemplate.exchange(
				LOCATION_URL, POST, new HttpEntity<>(json, headers), String.class);
		assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
	}

	private WebSocket connectWs(String token, CompletableFuture<String> peerLocationFuture)
			throws Exception {
		URI uri = URI.create("ws://localhost:" + port + "/ws/v1/transit?access_token=" + token);
		return HttpClient.newHttpClient()
				.newWebSocketBuilder()
				.buildAsync(uri, peerLocationListener(peerLocationFuture))
				.get(5, TimeUnit.SECONDS);
	}

	private static WebSocket.Listener peerLocationListener(CompletableFuture<String> target) {
		return new WebSocket.Listener() {

			private final StringBuilder buffer = new StringBuilder();

			@Override
			public void onOpen(WebSocket ws) {
				ws.request(1);
			}

			@Override
			public CompletionStage<?> onText(WebSocket ws, CharSequence data, boolean last) {
				buffer.append(data);
				if (last) {
					String msg = buffer.toString();
					buffer.setLength(0);
					if (msg.contains("\"peer_location\"")) {
						target.complete(msg);
					}
					else {
						ws.request(1);
					}
				}
				else {
					ws.request(1);
				}
				return null;
			}

			@Override
			public CompletionStage<?> onClose(WebSocket ws, int statusCode, String reason) {
				target.completeExceptionally(
						new RuntimeException("WS closed before peer_location: " + statusCode));
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
