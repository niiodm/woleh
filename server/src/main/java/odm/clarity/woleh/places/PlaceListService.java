package odm.clarity.woleh.places;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import odm.clarity.woleh.ws.WsSessionRegistry;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

import odm.clarity.woleh.common.error.PermissionDeniedException;
import odm.clarity.woleh.common.error.PlaceLimitExceededException;
import odm.clarity.woleh.common.error.PlaceNameValidationException;
import odm.clarity.woleh.common.error.UserNotFoundException;
import odm.clarity.woleh.model.PlaceListType;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.model.UserPlaceList;
import odm.clarity.woleh.places.dto.PlaceNamesResponse;
import odm.clarity.woleh.places.util.PlaceNameNormalizer;
import odm.clarity.woleh.repository.UserPlaceListRepository;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.subscription.EntitlementService;
import odm.clarity.woleh.subscription.Entitlements;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Business logic for reading and replacing a user's place-name lists.
 *
 * <p>Each PUT replaces the stored list atomically (full replacement — not append).
 * After a successful save the appropriate {@link MatchingService} dispatch method
 * is called so real-time match events can be pushed to connected WebSocket clients
 * (currently a no-op stub until step 2.5).
 */
@Service
@Transactional
public class PlaceListService {

	private static final String PERM_WATCH = "woleh.place.watch";
	private static final String PERM_BROADCAST = "woleh.place.broadcast";

	private final UserPlaceListRepository placeListRepository;
	private final UserRepository userRepository;
	private final EntitlementService entitlementService;
	private final PlaceNameNormalizer normalizer;
	private final MatchingService matchingService;
	private final MatchAdjacencyRegistry matchAdjacencyRegistry;
	private final WsSessionRegistry wsSessionRegistry;
	private final Counter watchPutCounter;
	private final Counter broadcastPutCounter;

	public PlaceListService(
			UserPlaceListRepository placeListRepository,
			UserRepository userRepository,
			EntitlementService entitlementService,
			PlaceNameNormalizer normalizer,
			MatchingService matchingService,
			MatchAdjacencyRegistry matchAdjacencyRegistry,
			WsSessionRegistry wsSessionRegistry,
			MeterRegistry meterRegistry) {
		this.placeListRepository = placeListRepository;
		this.userRepository = userRepository;
		this.entitlementService = entitlementService;
		this.normalizer = normalizer;
		this.matchingService = matchingService;
		this.matchAdjacencyRegistry = matchAdjacencyRegistry;
		this.wsSessionRegistry = wsSessionRegistry;
		this.watchPutCounter = Counter.builder("woleh.place.list.put")
				.tag("list_type", "watch")
				.description("Successful PUT operations on the watch place-name list")
				.register(meterRegistry);
		this.broadcastPutCounter = Counter.builder("woleh.place.list.put")
				.tag("list_type", "broadcast")
				.description("Successful PUT operations on the broadcast place-name list")
				.register(meterRegistry);
	}

	// ── watch list ────────────────────────────────────────────────────────

	/** Returns the user's current watch list (display names in insertion order). */
	@Transactional(readOnly = true)
	public PlaceNamesResponse getWatchList(Long userId) {
		requirePermission(userId, PERM_WATCH);
		return placeListRepository.findByUser_IdAndListType(userId, PlaceListType.WATCH)
				.map(l -> new PlaceNamesResponse(l.getDisplayNames()))
				.orElse(new PlaceNamesResponse(List.of()));
	}

	/**
	 * Replaces the user's watch list.
	 *
	 * <ul>
	 *   <li>Each name is validated (non-empty after trim; ≤ 200 code points).</li>
	 *   <li>Duplicates are removed by normalized equality; the first occurrence is kept.</li>
	 *   <li>Count after dedupe must not exceed {@code limits.placeWatchMax}.</li>
	 *   <li>An empty list clears the watch list.</li>
	 * </ul>
	 */
	public PlaceNamesResponse putWatchList(Long userId, List<String> rawNames) {
		Entitlements ent = requirePermission(userId, PERM_WATCH);

		DedupeResult deduped = validateAndDedupe(rawNames);

		if (deduped.displayNames().size() > ent.placeWatchMax()) {
			throw new PlaceLimitExceededException("watch", ent.placeWatchMax());
		}

		upsert(userId, PlaceListType.WATCH, deduped);
		watchPutCounter.increment();
		Set<Long> lostPeers = matchAdjacencyRegistry.rebuildAdjacencyForUser(userId);
		notifyLiveLocationAdjacencyLoss(userId, lostPeers);
		matchingService.dispatchWatchMatches(userId, deduped.normalizedNames());

		return new PlaceNamesResponse(deduped.displayNames());
	}

	// ── broadcast list ────────────────────────────────────────────────────

	/** Returns the user's current broadcast list in stored order (sequence is significant). */
	@Transactional(readOnly = true)
	public PlaceNamesResponse getBroadcastList(Long userId) {
		requirePermission(userId, PERM_BROADCAST);
		return placeListRepository.findByUser_IdAndListType(userId, PlaceListType.BROADCAST)
				.map(l -> new PlaceNamesResponse(l.getDisplayNames()))
				.orElse(new PlaceNamesResponse(List.of()));
	}

	/**
	 * Replaces the user's broadcast list.
	 *
	 * <ul>
	 *   <li>Each name is validated (non-empty after trim; ≤ 200 code points).</li>
	 *   <li>Duplicate normalized names are <em>rejected</em> with a 400 — broadcast order
	 *       is meaningful and ambiguous duplicates would corrupt the sequence.</li>
	 *   <li>Count must not exceed {@code limits.placeBroadcastMax}.</li>
	 *   <li>An empty list clears the broadcast list.</li>
	 * </ul>
	 */
	public PlaceNamesResponse putBroadcastList(Long userId, List<String> rawNames) {
		Entitlements ent = requirePermission(userId, PERM_BROADCAST);

		DedupeResult deduped = validateNoDuplicates(rawNames);

		if (deduped.displayNames().size() > ent.placeBroadcastMax()) {
			throw new PlaceLimitExceededException("broadcast", ent.placeBroadcastMax());
		}

		upsert(userId, PlaceListType.BROADCAST, deduped);
		broadcastPutCounter.increment();
		Set<Long> lostPeers = matchAdjacencyRegistry.rebuildAdjacencyForUser(userId);
		notifyLiveLocationAdjacencyLoss(userId, lostPeers);
		matchingService.dispatchBroadcastMatches(userId, deduped.normalizedNames());

		return new PlaceNamesResponse(deduped.displayNames());
	}

	// ── helpers ───────────────────────────────────────────────────────────

	/**
	 * When a place-list change breaks match adjacency, matched peers must drop each other's
	 * map markers ({@code peer_location_revoked}), same as turning off location sharing.
	 */
	private void notifyLiveLocationAdjacencyLoss(Long userId, Set<Long> lostPeers) {
		if (lostPeers.isEmpty()) {
			return;
		}
		String uidStr = String.valueOf(userId);
		Runnable notify = () -> {
			for (Long peerId : lostPeers) {
				wsSessionRegistry.sendPeerLocationRevoked(peerId, uidStr);
				wsSessionRegistry.sendPeerLocationRevoked(userId, String.valueOf(peerId));
			}
		};
		if (TransactionSynchronizationManager.isSynchronizationActive()) {
			TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
				@Override
				public void afterCommit() {
					notify.run();
				}
			});
		}
		else {
			notify.run();
		}
	}

	/**
	 * Checks that the user has the required permission; throws {@link PermissionDeniedException}
	 * otherwise. Returns the computed entitlements so callers can reuse the limit values.
	 */
	private Entitlements requirePermission(Long userId, String permission) {
		Entitlements ent = entitlementService.computeEntitlements(userId);
		if (!ent.permissions().contains(permission)) {
			throw new PermissionDeniedException(permission);
		}
		return ent;
	}

	/**
	 * Validates every raw name and deduplicates by normalized equality,
	 * preserving the first-occurrence display form and insertion order.
	 */
	private DedupeResult validateAndDedupe(List<String> rawNames) {
		List<String> displayResult = new ArrayList<>();
		List<String> normalizedResult = new ArrayList<>();
		Set<String> seen = new LinkedHashSet<>();

		for (String raw : rawNames) {
			normalizer.validatePlaceName(raw); // throws PlaceNameValidationException on bad input
			String norm = normalizer.normalize(raw);
			if (seen.add(norm)) {
				displayResult.add(raw);
				normalizedResult.add(norm);
			}
		}

		return new DedupeResult(displayResult, normalizedResult);
	}

	/** Upserts the {@code user_place_lists} row: creates it if absent, replaces lists if present. */
	private void upsert(Long userId, PlaceListType type, DedupeResult deduped) {
		UserPlaceList list = placeListRepository
				.findByUser_IdAndListType(userId, type)
				.orElseGet(() -> {
					User user = userRepository.findById(userId)
							.orElseThrow(() -> new UserNotFoundException(userId));
					return new UserPlaceList(user, type, List.of(), List.of());
				});

		list.setDisplayNames(deduped.displayNames());
		list.setNormalizedNames(deduped.normalizedNames());
		placeListRepository.save(list);
	}

	/**
	 * Validates every raw name and <em>rejects</em> the list if any two names share the
	 * same normalized form.  Used for broadcast lists where order is significant and
	 * silently dropping a duplicate would corrupt the intended sequence.
	 */
	private DedupeResult validateNoDuplicates(List<String> rawNames) {
		List<String> displayResult = new ArrayList<>();
		List<String> normalizedResult = new ArrayList<>();
		Set<String> seen = new LinkedHashSet<>();

		for (String raw : rawNames) {
			normalizer.validatePlaceName(raw);
			String norm = normalizer.normalize(raw);
			if (!seen.add(norm)) {
				throw new PlaceNameValidationException(
						"Duplicate place name in broadcast list (after normalization): \"" + raw + "\"");
			}
			displayResult.add(raw);
			normalizedResult.add(norm);
		}

		return new DedupeResult(displayResult, normalizedResult);
	}

	private record DedupeResult(List<String> displayNames, List<String> normalizedNames) {
	}
}
