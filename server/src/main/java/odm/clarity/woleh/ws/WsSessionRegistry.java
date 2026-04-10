package odm.clarity.woleh.ws;

import java.io.IOException;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;

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
 * Exposes a {@code woleh.ws.sessions.active} gauge so operations can track live connections.
 */
@Component
public class WsSessionRegistry {

	private static final Logger log = LoggerFactory.getLogger(WsSessionRegistry.class);

	private final ConcurrentHashMap<Long, WebSocketSession> sessions = new ConcurrentHashMap<>();
	private final ObjectMapper objectMapper;

	public WsSessionRegistry(ObjectMapper objectMapper, MeterRegistry meterRegistry) {
		this.objectMapper = objectMapper;
		Gauge.builder("woleh.ws.sessions.active", sessions, ConcurrentHashMap::size)
				.description("Number of currently active WebSocket sessions")
				.register(meterRegistry);
	}

	/** Returns the number of currently registered sessions. */
	public int sessionCount() {
		return sessions.size();
	}

	/** Registers a newly-established session. Replaces any stale session for the same user. */
	public void register(Long userId, WebSocketSession session) {
		sessions.put(userId, session);
	}

	/** Removes the session for {@code userId}, if present. */
	public void deregister(Long userId) {
		sessions.remove(userId);
	}

	/** Whether {@code userId} has a registered WebSocket session that is still open. */
	public boolean hasOpenSession(Long userId) {
		WebSocketSession session = sessions.get(userId);
		if (session == null) {
			return false;
		}
		if (!session.isOpen()) {
			sessions.remove(userId, session);
			return false;
		}
		return true;
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

	/**
	 * Sends a {@code peer_location} event to {@code recipientUserId}'s open WebSocket session.
	 * Used for match-scoped live location (MAP_LIVE_LOCATION_PLAN §3.3).
	 */
	public void sendPeerLocationEvent(Long recipientUserId, PeerLocationEvent event) {
		WebSocketSession session = sessions.get(recipientUserId);
		if (session == null || !session.isOpen()) {
			log.debug("sendPeerLocationEvent: no open session for recipientUserId={}, skipping", recipientUserId);
			return;
		}

		WsEnvelope<PeerLocationEvent> envelope = new WsEnvelope<>("peer_location", event);
		try {
			String json = objectMapper.writeValueAsString(envelope);
			session.sendMessage(new TextMessage(json));
			log.debug("sendPeerLocationEvent: sent publisher={} to recipientUserId={}",
					event.userId(), recipientUserId);
		}
		catch (JsonProcessingException e) {
			log.error("sendPeerLocationEvent: failed to serialise for recipientUserId={}", recipientUserId, e);
		}
		catch (IOException e) {
			log.warn("sendPeerLocationEvent: failed to send to recipientUserId={} — removing session",
					recipientUserId, e);
			sessions.remove(recipientUserId, session);
		}
	}

	/**
	 * Notifies {@code recipientUserId} that {@code publisherUserId} stopped location sharing
	 * (MAP_LIVE_LOCATION_PLAN §3.4).
	 */
	public void sendPeerLocationRevoked(Long recipientUserId, String publisherUserId) {
		WebSocketSession session = sessions.get(recipientUserId);
		if (session == null || !session.isOpen()) {
			log.debug("sendPeerLocationRevoked: no open session for recipientUserId={}, skipping",
					recipientUserId);
			return;
		}

		WsEnvelope<PeerLocationRevokedEvent> envelope =
				new WsEnvelope<>("peer_location_revoked", new PeerLocationRevokedEvent(publisherUserId));
		try {
			String json = objectMapper.writeValueAsString(envelope);
			session.sendMessage(new TextMessage(json));
			log.debug("sendPeerLocationRevoked: publisher={} → recipientUserId={}",
					publisherUserId, recipientUserId);
		}
		catch (JsonProcessingException e) {
			log.error("sendPeerLocationRevoked: serialise failed recipientUserId={}", recipientUserId, e);
		}
		catch (IOException e) {
			log.warn("sendPeerLocationRevoked: send failed recipientUserId={} — removing session",
					recipientUserId, e);
			sessions.remove(recipientUserId, session);
		}
	}
}
