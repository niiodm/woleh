package odm.clarity.woleh.ws;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

/**
 * Handles the lifecycle of {@code /ws/v1/transit} WebSocket connections.
 *
 * <ul>
 *   <li>On connect: reads {@code userId} from handshake attributes (set by
 *       {@link JwtHandshakeInterceptor}) and registers the session with {@link WsSessionRegistry}.
 *   <li>On close: deregisters the session.
 *   <li>Inbound text frames are discarded; the channel is server-push only.
 * </ul>
 */
@Component
public class TransitWebSocketHandler extends TextWebSocketHandler {

	private static final Logger log = LoggerFactory.getLogger(TransitWebSocketHandler.class);

	private final WsSessionRegistry registry;

	public TransitWebSocketHandler(WsSessionRegistry registry) {
		this.registry = registry;
	}

	@Override
	public void afterConnectionEstablished(WebSocketSession session) {
		Long userId = (Long) session.getAttributes().get(JwtHandshakeInterceptor.USER_ID_ATTR);
		if (userId == null) {
			log.warn("No userId in session attributes — closing session {}", session.getId());
			closeQuietly(session);
			return;
		}
		registry.register(userId, session);
		log.info("WS connected: userId={} sessionId={}", userId, session.getId());
	}

	@Override
	public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
		Long userId = (Long) session.getAttributes().get(JwtHandshakeInterceptor.USER_ID_ATTR);
		if (userId != null) {
			registry.deregister(userId);
		}
		log.info("WS disconnected: userId={} status={}", userId, status);
	}

	@Override
	protected void handleTextMessage(WebSocketSession session, TextMessage message) {
		log.debug("WS inbound message ignored (server-push only): sessionId={}", session.getId());
	}

	private static void closeQuietly(WebSocketSession session) {
		try {
			session.close(CloseStatus.POLICY_VIOLATION);
		}
		catch (Exception ignored) {
		}
	}
}
