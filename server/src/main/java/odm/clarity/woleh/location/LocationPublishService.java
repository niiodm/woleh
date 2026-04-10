package odm.clarity.woleh.location;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import odm.clarity.woleh.api.dto.PublishLocationRequest;
import odm.clarity.woleh.common.error.LocationSharingDisabledException;
import odm.clarity.woleh.common.error.PermissionDeniedException;
import odm.clarity.woleh.common.error.UserNotFoundException;
import java.time.Instant;
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

/**
 * Accepts authenticated location fixes and fans them out to matched peers over WebSocket
 * (MAP_LIVE_LOCATION_PLAN §3.2–3.3).
 */
@Service
public class LocationPublishService {

	private static final Logger log = LoggerFactory.getLogger(LocationPublishService.class);

	private static final String PERM_WATCH = "woleh.place.watch";
	private static final String PERM_BROADCAST = "woleh.place.broadcast";

	private final UserRepository userRepository;
	private final EntitlementService entitlementService;
	private final MatchAdjacencyRegistry matchAdjacencyRegistry;
	private final WsSessionRegistry wsSessionRegistry;

	public LocationPublishService(
			UserRepository userRepository,
			EntitlementService entitlementService,
			MatchAdjacencyRegistry matchAdjacencyRegistry,
			WsSessionRegistry wsSessionRegistry) {
		this.userRepository = userRepository;
		this.entitlementService = entitlementService;
		this.matchAdjacencyRegistry = matchAdjacencyRegistry;
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
		for (Long peerId : peers) {
			wsSessionRegistry.sendPeerLocationEvent(peerId, event);
		}

		if (log.isTraceEnabled()) {
			log.trace("location publish userId={} lat={} lng={} peers={}",
					userId, request.latitude(), request.longitude(), peers);
		}
	}

	@Transactional
	public boolean setLocationSharingEnabled(Long userId, boolean enabled) {
		User user = userRepository.findById(userId)
				.orElseThrow(() -> new UserNotFoundException(userId));
		requireWatchOrBroadcast(entitlementService.computeEntitlements(userId));
		user.setLocationSharingEnabled(enabled);
		userRepository.save(user);
		return user.isLocationSharingEnabled();
	}

	private static void requireWatchOrBroadcast(Entitlements ent) {
		if (ent.permissions().contains(PERM_WATCH) || ent.permissions().contains(PERM_BROADCAST)) {
			return;
		}
		throw new PermissionDeniedException(PERM_WATCH + " or " + PERM_BROADCAST);
	}
}
