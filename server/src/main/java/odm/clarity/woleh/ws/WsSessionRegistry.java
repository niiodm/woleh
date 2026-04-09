package odm.clarity.woleh.ws;

import java.io.IOException;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

/**
 * Thread-safe map of authenticated WebSocket sessions keyed by userId.
 *
 * <p>Step 2.6 adds session lifecycle methods and the heartbeat helper.
 * {@link #sendMatchEvent} is still a no-op stub; real push logic is wired in step 2.7.
 */
@Component
public class WsSessionRegistry {

	private static final Logger log = LoggerFactory.getLogger(WsSessionRegistry.class);

	private final ConcurrentHashMap<Long, WebSocketSession> sessions = new ConcurrentHashMap<>();

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
	 * Dispatches a {@code match} event to the given user.
	 * No-op stub — full implementation in step 2.7 once session serialisation is proven.
	 */
	public void sendMatchEvent(Long userId, List<String> matchedNames,
			Long counterpartyUserId, String kind) {
		log.debug("sendMatchEvent: userId={} counterparty={} matchedNames={} — no-op until step 2.7",
				userId, counterpartyUserId, matchedNames);
	}
}
