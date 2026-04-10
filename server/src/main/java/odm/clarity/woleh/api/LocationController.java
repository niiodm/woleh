package odm.clarity.woleh.api;

import jakarta.validation.Valid;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.api.dto.LocationSharingRequest;
import odm.clarity.woleh.api.dto.LocationSharingStateResponse;
import odm.clarity.woleh.api.dto.PublishLocationRequest;
import odm.clarity.woleh.location.LocationPublishService;
import odm.clarity.woleh.ratelimit.LocationPublishRateLimiter;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Match-scoped live location — REST surface (MAP_LIVE_LOCATION_PLAN §3.2, §3.4 toggle).
 */
@RestController
@RequestMapping("/api/v1/me")
public class LocationController {

	private final LocationPublishService locationPublishService;
	private final LocationPublishRateLimiter locationPublishRateLimiter;

	public LocationController(
			LocationPublishService locationPublishService,
			LocationPublishRateLimiter locationPublishRateLimiter) {
		this.locationPublishService = locationPublishService;
		this.locationPublishRateLimiter = locationPublishRateLimiter;
	}

	/**
	 * POST /api/v1/me/location — records one fix (WebSocket fan-out in §3.3).
	 * Requires {@code woleh.place.watch} or {@code woleh.place.broadcast} and sharing enabled.
	 */
	@PostMapping("/location")
	ResponseEntity<ApiEnvelope<Void>> publishLocation(
			@AuthenticationPrincipal Long userId,
			@RequestBody @Valid PublishLocationRequest request) {
		locationPublishRateLimiter.check(userId);
		locationPublishService.publish(userId, request);
		return ResponseEntity.ok(ApiEnvelope.success("Location recorded", null));
	}

	/**
	 * PUT /api/v1/me/location-sharing — opt in/out of publishing (FR-L2).
	 */
	@PutMapping("/location-sharing")
	ResponseEntity<ApiEnvelope<LocationSharingStateResponse>> setLocationSharing(
			@AuthenticationPrincipal Long userId,
			@RequestBody @Valid LocationSharingRequest request) {
		boolean enabled = locationPublishService.setLocationSharingEnabled(userId, request.enabled());
		return ResponseEntity.ok(ApiEnvelope.success(
				"Location sharing updated", new LocationSharingStateResponse(enabled)));
	}
}
