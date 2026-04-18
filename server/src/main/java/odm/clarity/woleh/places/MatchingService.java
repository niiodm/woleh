package odm.clarity.woleh.places;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;

import odm.clarity.woleh.location.GeoDistance;
import odm.clarity.woleh.location.LastKnownLocationStore;
import odm.clarity.woleh.model.PlaceListType;
import odm.clarity.woleh.model.UserPlaceList;
import odm.clarity.woleh.push.FcmService;
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
 *
 * <p>When several counterparties match, dispatch order follows increasing Haversine distance from
 * the initiator’s last-known published position to each counterparty’s (unknown positions last,
 * then by user id). Requires {@link LastKnownLocationStore}; absent initiator position falls back
 * to sorting by counterparty id only.
 */
@Service
@Transactional(readOnly = true)
public class MatchingService {

	private static final Logger log = LoggerFactory.getLogger(MatchingService.class);
	private static final String KIND = "broadcast_to_watch";

	private final UserPlaceListRepository placeListRepository;
	private final LastKnownLocationStore lastKnownLocationStore;
	private final WsSessionRegistry wsSessionRegistry;
	private final FcmService fcmService;
	private final Timer matchEvaluationTimer;

	public MatchingService(UserPlaceListRepository placeListRepository,
			LastKnownLocationStore lastKnownLocationStore,
			WsSessionRegistry wsSessionRegistry,
			FcmService fcmService,
			MeterRegistry meterRegistry) {
		this.placeListRepository = placeListRepository;
		this.lastKnownLocationStore = lastKnownLocationStore;
		this.wsSessionRegistry = wsSessionRegistry;
		this.fcmService = fcmService;
		this.matchEvaluationTimer = Timer.builder("woleh.match.evaluation")
				.description("Time to evaluate name intersections and dispatch match events")
				.register(meterRegistry);
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

		matchEvaluationTimer.record(() -> {
			Set<String> broadcastSet = new HashSet<>(normalizedBroadcastNames);
			List<CounterpartyMatch> matches = new ArrayList<>();

			for (UserPlaceList watchList : placeListRepository.findAllByListType(PlaceListType.WATCH)) {
				Long watcherUserId = watchList.getUserId();
				if (watcherUserId.equals(broadcastUserId)) {
					continue;
				}
				List<String> intersection = intersect(watchList.getNormalizedNames(), broadcastSet);
				if (intersection.isEmpty()) {
					continue;
				}
				matches.add(new CounterpartyMatch(watcherUserId, intersection));
			}

			sortCounterpartiesByClosestFirst(broadcastUserId, matches);

			for (CounterpartyMatch m : matches) {
				log.debug("broadcast match: broadcaster={} watcher={} names={}",
						broadcastUserId, m.counterpartyUserId(), m.intersection());
				sendMatchToUser(m.counterpartyUserId(), m.intersection(), broadcastUserId);
				sendMatchToUser(broadcastUserId, m.intersection(), m.counterpartyUserId());
			}
		});
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

		matchEvaluationTimer.record(() -> {
			Set<String> watchSet = new HashSet<>(normalizedWatchNames);
			List<CounterpartyMatch> matches = new ArrayList<>();

			for (UserPlaceList broadcastList : placeListRepository.findAllByListType(PlaceListType.BROADCAST)) {
				Long broadcasterUserId = broadcastList.getUserId();
				if (broadcasterUserId.equals(watchUserId)) {
					continue;
				}
				List<String> intersection = intersect(broadcastList.getNormalizedNames(), watchSet);
				if (intersection.isEmpty()) {
					continue;
				}
				matches.add(new CounterpartyMatch(broadcasterUserId, intersection));
			}

			sortCounterpartiesByClosestFirst(watchUserId, matches);

			for (CounterpartyMatch m : matches) {
				log.debug("watch match: watcher={} broadcaster={} names={}",
						watchUserId, m.counterpartyUserId(), m.intersection());
				sendMatchToUser(watchUserId, m.intersection(), m.counterpartyUserId());
				sendMatchToUser(m.counterpartyUserId(), m.intersection(), watchUserId);
			}
		});
	}

	// ── helpers ───────────────────────────────────────────────────────────

	private record CounterpartyMatch(Long counterpartyUserId, List<String> intersection) {
	}

	private void sortCounterpartiesByClosestFirst(long initiatorUserId, List<CounterpartyMatch> matches) {
		matches.sort(distanceComparatorForInitiator(initiatorUserId));
	}

	private Comparator<CounterpartyMatch> distanceComparatorForInitiator(long initiatorUserId) {
		return lastKnownLocationStore.get(initiatorUserId)
				.<Comparator<CounterpartyMatch>>map(origin -> Comparator
						.<CounterpartyMatch>comparingDouble(m -> lastKnownLocationStore.get(m.counterpartyUserId())
								.map(p -> GeoDistance.haversineMeters(
										origin.latitude(), origin.longitude(), p.latitude(), p.longitude()))
								.orElse(Double.POSITIVE_INFINITY))
						.thenComparingLong(CounterpartyMatch::counterpartyUserId))
				.orElseGet(() -> Comparator.comparingLong(CounterpartyMatch::counterpartyUserId));
	}

	private void sendMatchToUser(Long recipientUserId, List<String> intersection, Long counterpartyUserId) {
		wsSessionRegistry.sendMatchEvent(recipientUserId, intersection, counterpartyUserId, KIND);
		if (!wsSessionRegistry.hasOpenSession(recipientUserId)) {
			String names = String.join(", ", intersection);
			fcmService.sendNotification(
					recipientUserId,
					"Match found",
					"A vehicle covers your stops: " + names,
					Map.of("kind", "match", "counterpartyUserId", String.valueOf(counterpartyUserId)));
		}
	}

	/** Returns the normalized names from {@code candidates} that are also in {@code against}. */
	private static List<String> intersect(List<String> candidates, Set<String> against) {
		return candidates.stream()
				.filter(against::contains)
				.toList();
	}
}
