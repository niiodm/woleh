package odm.clarity.woleh.ws;

import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Central registry of live WebSocket sessions and the dispatch point for outbound messages.
 *
 * <p><b>Phase 2 step 2.6 stub:</b> Session registration/deregistration and heartbeat
 * machinery will be added in step 2.6 when the WebSocket endpoint is wired up.
 *
 * <p><b>Phase 2 step 2.7:</b> {@link #sendMatchEvent} will be completed to serialize
 * a {@code WsEnvelope<MatchEvent>} and write it to the owner's open session.
 * The current no-op is safe — if no session is open the event is simply not delivered
 * (the client will receive current match state on next connect).
 */
@Component
public class WsSessionRegistry {

	private static final Logger log = LoggerFactory.getLogger(WsSessionRegistry.class);

	/**
	 * Sends a {@code match} event to a connected user.
	 * If the user has no open session the event is silently dropped.
	 *
	 * <p>Completed in step 2.7 once the WebSocket infrastructure (step 2.6) exists.
	 */
	public void sendMatchEvent(Long userId, List<String> matchedNames,
			Long counterpartyUserId, String kind) {
		log.debug("sendMatchEvent: userId={} counterparty={} matchedNames={} — no-op until step 2.7",
				userId, counterpartyUserId, matchedNames);
	}
}
