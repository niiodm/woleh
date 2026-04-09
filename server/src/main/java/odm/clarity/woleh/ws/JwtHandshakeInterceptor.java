package odm.clarity.woleh.ws;

import java.util.Map;

import odm.clarity.woleh.security.JwtService;
import odm.clarity.woleh.subscription.EntitlementService;
import odm.clarity.woleh.subscription.Entitlements;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.HandshakeInterceptor;
import org.springframework.web.util.UriComponentsBuilder;

import io.jsonwebtoken.JwtException;

/**
 * Authenticates WebSocket upgrade requests per ADR 0001.
 *
 * <p>Reads {@code ?access_token=<jwt>} from the upgrade URL, validates the token with
 * {@link JwtService}, and checks that the user holds at least one place permission
 * ({@code woleh.place.watch} or {@code woleh.place.broadcast}).
 * Rejects with HTTP 403 if the token is absent, invalid, expired, or the user lacks
 * both place permissions.
 *
 * <p>On acceptance, stores {@code "userId"} (Long) in the handshake attributes map so
 * {@link TransitWebSocketHandler} can retrieve it in {@code afterConnectionEstablished}.
 */
@Component
public class JwtHandshakeInterceptor implements HandshakeInterceptor {

	static final String USER_ID_ATTR = "userId";

	private static final Logger log = LoggerFactory.getLogger(JwtHandshakeInterceptor.class);

	private final JwtService jwtService;
	private final EntitlementService entitlementService;

	public JwtHandshakeInterceptor(JwtService jwtService, EntitlementService entitlementService) {
		this.jwtService = jwtService;
		this.entitlementService = entitlementService;
	}

	@Override
	public boolean beforeHandshake(ServerHttpRequest request, ServerHttpResponse response,
			WebSocketHandler wsHandler, Map<String, Object> attributes) {

		String token = UriComponentsBuilder.fromUri(request.getURI())
				.build().getQueryParams().getFirst("access_token");

		if (token == null || token.isBlank()) {
			log.debug("WS upgrade rejected: missing access_token");
			response.setStatusCode(HttpStatus.FORBIDDEN);
			return false;
		}

		long userId;
		try {
			userId = jwtService.parseUserId(token);
		}
		catch (JwtException | IllegalArgumentException e) {
			log.debug("WS upgrade rejected: invalid token — {}", e.getMessage());
			response.setStatusCode(HttpStatus.FORBIDDEN);
			return false;
		}

		try {
			Entitlements ent = entitlementService.computeEntitlements(userId);
			boolean hasPlacePermission = ent.permissions().contains("woleh.place.watch")
					|| ent.permissions().contains("woleh.place.broadcast");
			if (!hasPlacePermission) {
				log.debug("WS upgrade rejected: userId={} has no place permission", userId);
				response.setStatusCode(HttpStatus.FORBIDDEN);
				return false;
			}
		}
		catch (Exception e) {
			log.warn("WS upgrade rejected: entitlement check failed for userId={}", userId, e);
			response.setStatusCode(HttpStatus.FORBIDDEN);
			return false;
		}

		attributes.put(USER_ID_ATTR, userId);
		log.debug("WS upgrade accepted: userId={}", userId);
		return true;
	}

	@Override
	public void afterHandshake(ServerHttpRequest request, ServerHttpResponse response,
			WebSocketHandler wsHandler, Exception exception) {
		// no-op
	}
}
