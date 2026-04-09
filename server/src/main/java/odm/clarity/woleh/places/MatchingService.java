package odm.clarity.woleh.places;

import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Dispatches real-time match events to connected WebSocket clients when a
 * broadcast or watch list is updated and intersects a complementary list.
 *
 * <p><b>Phase 2 step 2.5 stub:</b> Both dispatch methods are intentional no-ops here.
 * The real implementation (intersection query + {@code WsSessionRegistry} push) will be
 * added in step 2.5 when the WebSocket infrastructure exists.  {@link PlaceListService}
 * already calls these methods on every successful PUT so the wire-up is already in place.
 */
@Service
public class MatchingService {

	private static final Logger log = LoggerFactory.getLogger(MatchingService.class);

	/**
	 * Called after a user's watch list is saved.
	 * Will scan all broadcast lists for intersections and push {@code match} events.
	 */
	public void dispatchWatchMatches(Long watchUserId, List<String> normalizedWatchNames) {
		log.debug("dispatchWatchMatches: userId={} names={} — no-op until step 2.5",
				watchUserId, normalizedWatchNames);
	}

	/**
	 * Called after a user's broadcast list is saved.
	 * Will scan all watch lists for intersections and push {@code match} events.
	 */
	public void dispatchBroadcastMatches(Long broadcastUserId, List<String> normalizedBroadcastNames) {
		log.debug("dispatchBroadcastMatches: userId={} names={} — no-op until step 2.5",
				broadcastUserId, normalizedBroadcastNames);
	}
}
