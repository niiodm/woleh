package odm.clarity.woleh.places;

import jakarta.validation.Valid;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.places.dto.PlaceNamesRequest;
import odm.clarity.woleh.places.dto.PlaceNamesResponse;
import odm.clarity.woleh.ratelimit.PlaceListRateLimiter;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Place-name list endpoints — watch and broadcast (API_CONTRACT.md §6.7–§6.10).
 * Permission and limit enforcement are handled in {@link PlaceListService}.
 * Rate limiting (writes only) is enforced by {@link PlaceListRateLimiter}.
 */
@RestController
@RequestMapping("/api/v1/me/places")
public class PlaceListController {

	private final PlaceListService placeListService;
	private final PlaceListRateLimiter rateLimiter;

	public PlaceListController(PlaceListService placeListService, PlaceListRateLimiter rateLimiter) {
		this.placeListService = placeListService;
		this.rateLimiter = rateLimiter;
	}

	// ── watch list ────────────────────────────────────────────────────────

	/** GET /api/v1/me/places/watch — requires {@code woleh.place.watch}. */
	@GetMapping("/watch")
	ResponseEntity<ApiEnvelope<PlaceNamesResponse>> getWatch(
			@AuthenticationPrincipal Long userId) {
		return ResponseEntity.ok(
				ApiEnvelope.success("OK", placeListService.getWatchList(userId)));
	}

	/**
	 * PUT /api/v1/me/places/watch — replaces the watch list; requires {@code woleh.place.watch}.
	 * Send {@code {"names":[]}} to clear.
	 */
	@PutMapping("/watch")
	ResponseEntity<ApiEnvelope<PlaceNamesResponse>> putWatch(
			@AuthenticationPrincipal Long userId,
			@RequestBody @Valid PlaceNamesRequest request) {
		rateLimiter.checkWatch(userId);
		return ResponseEntity.ok(
				ApiEnvelope.success("Watch list updated",
						placeListService.putWatchList(userId, request.names())));
	}

	// ── broadcast list ────────────────────────────────────────────────────

	/** GET /api/v1/me/places/broadcast — requires {@code woleh.place.broadcast}. */
	@GetMapping("/broadcast")
	ResponseEntity<ApiEnvelope<PlaceNamesResponse>> getBroadcast(
			@AuthenticationPrincipal Long userId) {
		return ResponseEntity.ok(
				ApiEnvelope.success("OK", placeListService.getBroadcastList(userId)));
	}

	/**
	 * PUT /api/v1/me/places/broadcast — replaces the broadcast list; requires
	 * {@code woleh.place.broadcast}.  Duplicate normalized names are rejected with 400.
	 * Send {@code {"names":[]}} to clear.
	 */
	@PutMapping("/broadcast")
	ResponseEntity<ApiEnvelope<PlaceNamesResponse>> putBroadcast(
			@AuthenticationPrincipal Long userId,
			@RequestBody @Valid PlaceNamesRequest request) {
		rateLimiter.checkBroadcast(userId);
		return ResponseEntity.ok(
				ApiEnvelope.success("Broadcast list updated",
						placeListService.putBroadcastList(userId, request.names())));
	}
}
