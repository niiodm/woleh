package odm.clarity.woleh.location;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import odm.clarity.woleh.api.dto.PublishLocationRequest;
import odm.clarity.woleh.common.error.LocationSharingDisabledException;
import odm.clarity.woleh.common.error.PermissionDeniedException;
import odm.clarity.woleh.common.error.UserNotFoundException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Set;

import odm.clarity.woleh.model.User;
import odm.clarity.woleh.places.MatchAdjacencyRegistry;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.subscription.EntitlementService;
import odm.clarity.woleh.subscription.Entitlements;
import odm.clarity.woleh.ws.PeerLocationEvent;
import odm.clarity.woleh.ws.WsSessionRegistry;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Accepts authenticated location fixes and fans them out to matched peers over WebSocket
 * (MAP_LIVE_LOCATION_PLAN §3.2–3.3). Turning sharing off notifies peers (§3.4).
 *
 * <p>Successful publishes update {@link LastKnownLocationStore}; peer fan-out is ordered by
 * increasing Haversine distance from this fix to each peer’s last-known position (unknown last,
 * then by peer id).
 */
@Service
public class LocationPublishService {

	private static final Logger log = LoggerFactory.getLogger(LocationPublishService.class);

	private static final String PERM_WATCH = "woleh.place.watch";
	private static final String PERM_BROADCAST = "woleh.place.broadcast";

	private final UserRepository userRepository;
	private final EntitlementService entitlementService;
	private final MatchAdjacencyRegistry matchAdjacencyRegistry;
	private final LastKnownLocationStore lastKnownLocationStore;
	private final WsSessionRegistry wsSessionRegistry;

	public LocationPublishService(
			UserRepository userRepository,
			EntitlementService entitlementService,
			MatchAdjacencyRegistry matchAdjacencyRegistry,
			LastKnownLocationStore lastKnownLocationStore,
			WsSessionRegistry wsSessionRegistry) {
		this.userRepository = userRepository;
		this.entitlementService = entitlementService;
		this.matchAdjacencyRegistry = matchAdjacencyRegistry;
		this.lastKnownLocationStore = lastKnownLocationStore;
		this.wsSessionRegistry = wsSessionRegistry;
	}

	/**
	 * Validates and fans out {@code peer_location} to open WS sessions of users in
	 * {@link MatchAdjacencyRegistry} for {@code userId}. No DB writes — not transactional.
	 */
	public void publish(Long userId, PublishLocationRequest request) {
		User user = userRepository.findById(userId)
				.orElseThrow(() -> new UserNotFoundException(userId));

		requireWatchOrBroadcast(entitlementService.computeEntitlements(userId));

		if (!user.isLocationSharingEnabled()) {
			throw new LocationSharingDisabledException();
		}

		lastKnownLocationStore.put(userId, request.latitude(), request.longitude());

		Instant receivedAt = Instant.now();
		PeerLocationEvent event = new PeerLocationEvent(
				String.valueOf(userId),
				request.latitude(),
				request.longitude(),
				request.accuracyMeters(),
				request.heading(),
				request.speed(),
				receivedAt);

		Set<Long> peers = matchAdjacencyRegistry.getCounterparties(userId);
		List<Long> orderedPeers = sortPeerIdsByClosestFirst(
				userId, request.latitude(), request.longitude(), peers);

		for (Long peerId : orderedPeers) {
			wsSessionRegistry.sendPeerLocationEvent(peerId, event);
		}

		if (log.isTraceEnabled()) {
			log.trace("location publish userId={} lat={} lng={} peers={}",
					userId, request.latitude(), request.longitude(), orderedPeers);
		}
	}

	/**
	 * Peers with a last-known position sort by Haversine distance ascending; peers without sort
	 * after, then by id for stability.
	 */
	private List<Long> sortPeerIdsByClosestFirst(
			long publisherUserId, double originLat, double originLon, Set<Long> peers) {
		List<Long> peerIds = new ArrayList<>(peers);
		peerIds.remove(Long.valueOf(publisherUserId));
		peerIds.sort(Comparator
				.<Long>comparingDouble(peerId -> lastKnownLocationStore.get(peerId)
						.map(p -> GeoDistance.haversineMeters(
								originLat, originLon, p.latitude(), p.longitude()))
						.orElse(Double.POSITIVE_INFINITY))
				.thenComparingLong(id -> id));
		return peerIds;
	}

	@Transactional
	public boolean setLocationSharingEnabled(Long userId, boolean enabled) {
		User user = userRepository.findById(userId)
				.orElseThrow(() -> new UserNotFoundException(userId));
		requireWatchOrBroadcast(entitlementService.computeEntitlements(userId));

		boolean wasEnabled = user.isLocationSharingEnabled();
		user.setLocationSharingEnabled(enabled);
		userRepository.save(user);

		// §3.4: tell matched peers to drop this user's marker (after successful commit).
		if (wasEnabled && !enabled) {
			Set<Long> peers = Set.copyOf(matchAdjacencyRegistry.getCounterparties(userId));
			String publisherId = String.valueOf(userId);
			Runnable notify = () -> {
				for (Long peerId : peers) {
					wsSessionRegistry.sendPeerLocationRevoked(peerId, publisherId);
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

		return user.isLocationSharingEnabled();
	}

	private static void requireWatchOrBroadcast(Entitlements ent) {
		if (ent.permissions().contains(PERM_WATCH) || ent.permissions().contains(PERM_BROADCAST)) {
			return;
		}
		throw new PermissionDeniedException(PERM_WATCH + " or " + PERM_BROADCAST);
	}
}
