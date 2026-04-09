package odm.clarity.woleh.places;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

import odm.clarity.woleh.model.PlaceListType;
import odm.clarity.woleh.model.UserPlaceList;
import odm.clarity.woleh.repository.UserPlaceListRepository;
import odm.clarity.woleh.ws.WsSessionRegistry;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Finds real-time matches between broadcast and watch place-name lists and
 * dispatches {@code match} events to connected WebSocket clients via {@link WsSessionRegistry}.
 *
 * <p>Intersection strategy (v1): load all complementary lists with
 * {@link UserPlaceListRepository#findAllByListType} and compute the intersection in memory.
 * This is O(n active lists) and appropriate for staging scale.
 * TODO: If needed, replace with a PostgreSQL {@code jsonb} overlap query or a separate
 * normalized-names join table — document the change in an ADR before implementing.
 *
 * <p>Both the party whose list changed <em>and</em> each matched counterparty are notified
 * so operators and riders can both see new matches in their connected sessions.
 */
@Service
@Transactional(readOnly = true)
public class MatchingService {

	private static final Logger log = LoggerFactory.getLogger(MatchingService.class);
	private static final String KIND = "broadcast_to_watch";

	private final UserPlaceListRepository placeListRepository;
	private final WsSessionRegistry wsSessionRegistry;

	public MatchingService(UserPlaceListRepository placeListRepository,
			WsSessionRegistry wsSessionRegistry) {
		this.placeListRepository = placeListRepository;
		this.wsSessionRegistry = wsSessionRegistry;
	}

	/**
	 * Called after a user's <em>broadcast</em> list is saved.
	 * Scans all watch lists for name intersection and notifies both the matching
	 * watcher and the broadcaster.
	 */
	public void dispatchBroadcastMatches(Long broadcastUserId, List<String> normalizedBroadcastNames) {
		if (normalizedBroadcastNames.isEmpty()) {
			return;
		}

		Set<String> broadcastSet = new HashSet<>(normalizedBroadcastNames);

		for (UserPlaceList watchList : placeListRepository.findAllByListType(PlaceListType.WATCH)) {
			List<String> intersection = intersect(watchList.getNormalizedNames(), broadcastSet);
			if (intersection.isEmpty()) {
				continue;
			}

			Long watcherUserId = watchList.getUserId();
			log.debug("broadcast match: broadcaster={} watcher={} names={}",
					broadcastUserId, watcherUserId, intersection);

			// Notify the watcher that a matching broadcast is active.
			wsSessionRegistry.sendMatchEvent(watcherUserId, intersection, broadcastUserId, KIND);
			// Notify the broadcaster that a rider is watching their route.
			wsSessionRegistry.sendMatchEvent(broadcastUserId, intersection, watcherUserId, KIND);
		}
	}

	/**
	 * Called after a user's <em>watch</em> list is saved.
	 * Scans all broadcast lists for name intersection and notifies both the matching
	 * broadcaster and the watcher.
	 */
	public void dispatchWatchMatches(Long watchUserId, List<String> normalizedWatchNames) {
		if (normalizedWatchNames.isEmpty()) {
			return;
		}

		Set<String> watchSet = new HashSet<>(normalizedWatchNames);

		for (UserPlaceList broadcastList : placeListRepository.findAllByListType(PlaceListType.BROADCAST)) {
			List<String> intersection = intersect(broadcastList.getNormalizedNames(), watchSet);
			if (intersection.isEmpty()) {
				continue;
			}

			Long broadcasterUserId = broadcastList.getUserId();
			log.debug("watch match: watcher={} broadcaster={} names={}",
					watchUserId, broadcasterUserId, intersection);

			// Notify the watcher that a matching broadcast exists.
			wsSessionRegistry.sendMatchEvent(watchUserId, intersection, broadcasterUserId, KIND);
			// Notify the broadcaster that a new rider is watching their route.
			wsSessionRegistry.sendMatchEvent(broadcasterUserId, intersection, watchUserId, KIND);
		}
	}

	// ── helpers ───────────────────────────────────────────────────────────

	/** Returns the normalized names from {@code candidates} that are also in {@code against}. */
	private static List<String> intersect(List<String> candidates, Set<String> against) {
		return candidates.stream()
				.filter(against::contains)
				.toList();
	}
}
