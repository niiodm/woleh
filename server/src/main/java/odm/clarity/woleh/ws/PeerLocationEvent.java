package odm.clarity.woleh.ws;

import java.time.Instant;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Data payload for a {@code peer_location} WebSocket event (MAP_LIVE_LOCATION_PLAN §3.3).
 * {@code userId} is the publisher (broadcaster or watcher sharing their fix).
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record PeerLocationEvent(
		String userId,
		double latitude,
		double longitude,
		Double accuracyMeters,
		Double heading,
		Double speed,
		Instant receivedAt) {
}
