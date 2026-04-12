package odm.clarity.woleh.ws;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Sends a {@code {"type":"heartbeat","data":"ping"}} frame to all open WebSocket sessions
 * every 15 seconds (API_CONTRACT.md §8).
 *
 * <p>Dead sessions (closed or error on send) are evicted by {@link WsSessionRegistry#sendToAllOpen}.
 */
@Component
public class WsHeartbeatScheduler {

	private static final Logger log = LoggerFactory.getLogger(WsHeartbeatScheduler.class);

	private final WsSessionRegistry registry;
	private final String heartbeatJson;

	public WsHeartbeatScheduler(WsSessionRegistry registry, ObjectMapper objectMapper) {
		this.registry = registry;
		try {
			this.heartbeatJson = objectMapper.writeValueAsString(new WsEnvelope<>("heartbeat", "ping"));
		}
		catch (JsonProcessingException e) {
			throw new IllegalStateException("Failed to serialise heartbeat envelope", e);
		}
	}

	@Scheduled(fixedDelay = 15_000)
	public void sendHeartbeats() {
		int n = registry.sessionCount();
		log.debug("Sending WebSocket heartbeat (ping) to {} open session(s)", n);
		registry.sendToAllOpen(heartbeatJson);
	}
}
