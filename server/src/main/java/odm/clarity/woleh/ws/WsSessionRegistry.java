package odm.clarity.woleh.ws;

import java.io.IOException;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Thread-safe map of authenticated WebSocket sessions keyed by userId.
 *
 * <p>Manages session lifecycle (register / deregister) and outbound message dispatch.
 */
@Component
public class WsSessionRegistry {

	private static final Logger log = LoggerFactory.getLogger(WsSessionRegistry.class);

	private final ConcurrentHashMap<Long, WebSocketSession> sessions = new ConcurrentHashMap<>();
	private final ObjectMapper objectMapper;

	public WsSessionRegistry(ObjectMapper objectMapper) {
		this.objectMapper = objectMapper;
	}

	/** Registers a newly-established session. Replaces any stale session for the same user. */
	public void register(Long userId, WebSocketSession session) {
		sessions.put(userId, session);
	}

	/** Removes the session for {@code userId}, if present. */
	public void deregister(Long userId) {
		sessions.remove(userId);
	}

	/**
	 * Sends {@code messageJson} to every open session; automatically deregisters sessions
	 * whose underlying connection has closed or errors on send.
	 */
	public void sendToAllOpen(String messageJson) {
		sessions.forEach((userId, session) -> {
			if (!session.isOpen()) {
				sessions.remove(userId, session);
				return;
			}
			try {
				session.sendMessage(new TextMessage(messageJson));
			}
			catch (IOException e) {
				log.warn("Failed to send to userId={} — removing session", userId, e);
				sessions.remove(userId, session);
			}
		});
	}

	/**
	 * Dispatches a {@code match} event to {@code userId}'s open WebSocket session.
	 *
	 * <p>Silently skips if the user has no open session — they will see current matches
	 * the next time they connect and their lists are queried.
	 */
	public void sendMatchEvent(Long userId, List<String> matchedNames,
			Long counterpartyUserId, String kind) {
		WebSocketSession session = sessions.get(userId);
		if (session == null || !session.isOpen()) {
			log.debug("sendMatchEvent: no open session for userId={}, skipping", userId);
			return;
		}

		MatchEvent event = new MatchEvent(matchedNames, String.valueOf(counterpartyUserId), kind);
		WsEnvelope<MatchEvent> envelope = new WsEnvelope<>("match", event);
		try {
			String json = objectMapper.writeValueAsString(envelope);
			session.sendMessage(new TextMessage(json));
			log.debug("sendMatchEvent: sent to userId={} matchedNames={}", userId, matchedNames);
		}
		catch (JsonProcessingException e) {
			log.error("sendMatchEvent: failed to serialise event for userId={}", userId, e);
		}
		catch (IOException e) {
			log.warn("sendMatchEvent: failed to send to userId={} — removing session", userId, e);
			sessions.remove(userId, session);
		}
	}
}
