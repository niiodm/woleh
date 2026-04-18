package odm.clarity.woleh.location;

import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.stereotype.Component;

/**
 * In-process cache of each user’s most recent accepted location publish.
 *
 * <p>Used for best-effort ordering of WebSocket fan-out (closest peers first). This is not a source
 * of truth: entries are absent for users who have never published, values become stale between
 * publishes, the map is cleared on JVM restart, and it is not shared across multiple application
 * instances (see ADR 0008).
 */
@Component
public class LastKnownLocationStore {

	private final ConcurrentHashMap<Long, LatLon> byUserId = new ConcurrentHashMap<>();

	/** Overwrites any prior coordinates for {@code userId}. */
	public void put(long userId, double latitude, double longitude) {
		byUserId.put(userId, new LatLon(latitude, longitude));
	}

	/** Last stored point for {@code userId}, if any. */
	public Optional<LatLon> get(long userId) {
		return Optional.ofNullable(byUserId.get(userId));
	}
}
