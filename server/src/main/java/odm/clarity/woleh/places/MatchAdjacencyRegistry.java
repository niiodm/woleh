package odm.clarity.woleh.places;

import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

import odm.clarity.woleh.model.PlaceListType;
import odm.clarity.woleh.model.UserPlaceList;
import odm.clarity.woleh.repository.UserPlaceListRepository;

import org.springframework.stereotype.Component;

/**
 * In-memory, bidirectional graph of users who are <strong>currently matched</strong> for
 * match-scoped features (e.g. live location): non-empty intersection of one party's
 * {@link PlaceListType#BROADCAST} normalized names and the other's {@link PlaceListType#WATCH}
 * normalized names — the same rule as {@link MatchingService}.
 *
 * <p>Rebuilt for a user whenever their watch or broadcast list is saved ({@link PlaceListService}).
 * Not synchronized across JVMs; see {@code docs/adr/0008-match-scoped-live-location.md}.
 */
@Component
public class MatchAdjacencyRegistry {

	private final UserPlaceListRepository placeListRepository;

	/** userId → counterparties (matched peers). */
	private final Map<Long, Set<Long>> adjacency = new ConcurrentHashMap<>();

	public MatchAdjacencyRegistry(UserPlaceListRepository placeListRepository) {
		this.placeListRepository = placeListRepository;
	}

	/**
	 * Drops all edges for {@code userId}, recomputes their counterparties from the database,
	 * and re-adds bidirectional edges. Safe to call after each place-list PUT.
	 *
	 * @return counterparties that {@code userId} was matched to immediately before this rebuild
	 *         but is no longer matched to afterward (for {@code peer_location_revoked} fan-out).
	 */
	public Set<Long> rebuildAdjacencyForUser(Long userId) {
		Set<Long> before = getCounterparties(userId);
		removeAllEdgesForUser(userId);
		for (Long peerId : computeCounterparties(userId)) {
			addBidirectional(userId, peerId);
		}
		Set<Long> after = getCounterparties(userId);
		Set<Long> lost = new HashSet<>(before);
		lost.removeAll(after);
		return lost;
	}

	/** Snapshot of user IDs matched to {@code userId} (empty if none). */
	public Set<Long> getCounterparties(Long userId) {
		Set<Long> s = adjacency.get(userId);
		if (s == null || s.isEmpty()) {
			return Set.of();
		}
		return Set.copyOf(s);
	}

	// ── graph maintenance ───────────────────────────────────────────────

	private void removeAllEdgesForUser(Long userId) {
		Set<Long> peers = adjacency.remove(userId);
		if (peers == null) {
			return;
		}
		for (Long p : peers) {
			Set<Long> back = adjacency.get(p);
			if (back != null) {
				back.remove(userId);
				if (back.isEmpty()) {
					adjacency.remove(p);
				}
			}
		}
	}

	private void addBidirectional(Long a, Long b) {
		if (a.equals(b)) {
			return;
		}
		adjacency.computeIfAbsent(a, k -> ConcurrentHashMap.newKeySet()).add(b);
		adjacency.computeIfAbsent(b, k -> ConcurrentHashMap.newKeySet()).add(a);
	}

	// ── matching logic (aligned with MatchingService) ─────────────────────

	private Set<Long> computeCounterparties(Long userId) {
		Set<Long> result = new HashSet<>();

		Optional<UserPlaceList> broadcastOpt =
				placeListRepository.findByUser_IdAndListType(userId, PlaceListType.BROADCAST);
		Optional<UserPlaceList> watchOpt =
				placeListRepository.findByUser_IdAndListType(userId, PlaceListType.WATCH);

		if (broadcastOpt.isPresent()) {
			List<String> bNames = broadcastOpt.get().getNormalizedNames();
			if (!bNames.isEmpty()) {
				Set<String> broadcastSet = new HashSet<>(bNames);
				for (UserPlaceList watchList : placeListRepository.findAllByListType(PlaceListType.WATCH)) {
					Long wid = watchList.getUserId();
					if (wid.equals(userId)) {
						continue;
					}
					if (!intersect(watchList.getNormalizedNames(), broadcastSet).isEmpty()) {
						result.add(wid);
					}
				}
			}
		}

		if (watchOpt.isPresent()) {
			List<String> wNames = watchOpt.get().getNormalizedNames();
			if (!wNames.isEmpty()) {
				Set<String> watchSet = new HashSet<>(wNames);
				for (UserPlaceList broadcastList : placeListRepository.findAllByListType(PlaceListType.BROADCAST)) {
					Long bid = broadcastList.getUserId();
					if (bid.equals(userId)) {
						continue;
					}
					if (!intersect(broadcastList.getNormalizedNames(), watchSet).isEmpty()) {
						result.add(bid);
					}
				}
			}
		}

		return result;
	}

	private static List<String> intersect(List<String> candidates, Set<String> against) {
		return candidates.stream()
				.filter(against::contains)
				.toList();
	}
}
