package odm.clarity.woleh.api;

import jakarta.validation.Valid;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.api.dto.MeResponse;
import odm.clarity.woleh.api.dto.PatchProfileRequest;
import odm.clarity.woleh.common.error.UserNotFoundException;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.subscription.Entitlements;
import odm.clarity.woleh.subscription.EntitlementService;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Session and profile endpoints.
 * Entitlements (permissions, tier, limits) are computed by {@link EntitlementService}
 * from the user's active subscription — not hard-coded (API_CONTRACT.md §6.3, §6.4).
 */
@RestController
@RequestMapping("/api/v1")
public class MeController {

	private final UserRepository userRepository;
	private final EntitlementService entitlementService;

	public MeController(UserRepository userRepository, EntitlementService entitlementService) {
		this.userRepository = userRepository;
		this.entitlementService = entitlementService;
	}

	/** GET /api/v1/me — returns profile + computed entitlements (API_CONTRACT.md §6.3). */
	@GetMapping("/me")
	ResponseEntity<ApiEnvelope<MeResponse>> me(@AuthenticationPrincipal Long userId) {
		User user = userRepository.findById(userId)
				.orElseThrow(() -> new UserNotFoundException(userId));
		Entitlements entitlements = entitlementService.computeEntitlements(userId);
		return ResponseEntity.ok(ApiEnvelope.success("OK", toMeResponse(user, entitlements)));
	}

	/**
	 * PATCH /api/v1/me/profile — partial update of mutable profile fields (API_CONTRACT.md §6.4).
	 * Permission {@code woleh.account.profile} is held by all users (free and paid).
	 */
	@PatchMapping("/me/profile")
	ResponseEntity<ApiEnvelope<MeResponse>> patchProfile(
			@AuthenticationPrincipal Long userId,
			@RequestBody @Valid PatchProfileRequest request) {

		User user = userRepository.findById(userId)
				.orElseThrow(() -> new UserNotFoundException(userId));

		if (request.displayName() != null) {
			user.setDisplayName(request.displayName());
			userRepository.save(user);
		}

		Entitlements entitlements = entitlementService.computeEntitlements(userId);
		return ResponseEntity.ok(ApiEnvelope.success("Profile updated", toMeResponse(user, entitlements)));
	}

	// ── helpers ──────────────────────────────────────────────────────────────

	private static MeResponse toMeResponse(User user, Entitlements e) {
		return new MeResponse(
				new MeResponse.Profile(
						String.valueOf(user.getId()),
						user.getPhoneE164(),
						user.getDisplayName()),
				e.permissions(),
				e.tier(),
				new MeResponse.Limits(e.placeWatchMax(), e.placeBroadcastMax()),
				new MeResponse.Subscription(e.subscriptionStatus(), e.currentPeriodEnd(), e.inGracePeriod()));
	}
}
