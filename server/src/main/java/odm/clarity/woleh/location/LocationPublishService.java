package odm.clarity.woleh.location;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import odm.clarity.woleh.api.dto.PublishLocationRequest;
import odm.clarity.woleh.common.error.LocationSharingDisabledException;
import odm.clarity.woleh.common.error.PermissionDeniedException;
import odm.clarity.woleh.common.error.UserNotFoundException;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.subscription.EntitlementService;
import odm.clarity.woleh.subscription.Entitlements;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Accepts authenticated location fixes for match-scoped fan-out (Phase 4).
 * WebSocket delivery is {@linkplain odm.clarity.woleh.ws.WsSessionRegistry separate (§3.3)}.
 */
@Service
public class LocationPublishService {

	private static final Logger log = LoggerFactory.getLogger(LocationPublishService.class);

	private static final String PERM_WATCH = "woleh.place.watch";
	private static final String PERM_BROADCAST = "woleh.place.broadcast";

	private final UserRepository userRepository;
	private final EntitlementService entitlementService;

	public LocationPublishService(
			UserRepository userRepository,
			EntitlementService entitlementService) {
		this.userRepository = userRepository;
		this.entitlementService = entitlementService;
	}

	@Transactional
	public void publish(Long userId, PublishLocationRequest request) {
		User user = userRepository.findById(userId)
				.orElseThrow(() -> new UserNotFoundException(userId));

		requireWatchOrBroadcast(entitlementService.computeEntitlements(userId));

		if (!user.isLocationSharingEnabled()) {
			throw new LocationSharingDisabledException();
		}

		if (log.isTraceEnabled()) {
			log.trace("location publish accepted userId={} lat={} lng={}",
					userId, request.latitude(), request.longitude());
		}
		// Fan-out to MatchAdjacencyRegistry peers: MAP_LIVE_LOCATION_PLAN §3.3.
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
