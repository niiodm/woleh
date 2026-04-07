package odm.clarity.woleh.api;

import java.util.List;

import jakarta.validation.Valid;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.api.dto.MeResponse;
import odm.clarity.woleh.api.dto.PatchProfileRequest;
import odm.clarity.woleh.common.error.UserNotFoundException;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.UserRepository;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Session and profile endpoint.
 * Phase 0: all authenticated users receive free-tier entitlements (PRD §13.1, §13.5).
 */
@RestController
@RequestMapping("/api/v1")
public class MeController {

	/**
	 * Free-tier permissions granted to every account until a paid subscription is active.
	 * Order matches API_CONTRACT.md §4.
	 */
	private static final List<String> FREE_PERMISSIONS = List.of(
			"woleh.account.profile",
			"woleh.plans.read",
			"woleh.place.watch");

	private static final MeResponse.Limits FREE_LIMITS = new MeResponse.Limits(5, 0);
	private static final MeResponse.Subscription NO_SUBSCRIPTION =
			new MeResponse.Subscription("none", null, false);

	private final UserRepository userRepository;

	public MeController(UserRepository userRepository) {
		this.userRepository = userRepository;
	}

	/** GET /api/v1/me — returns profile + free-tier entitlements (API_CONTRACT.md §6.3). */
	@GetMapping("/me")
	ResponseEntity<ApiEnvelope<MeResponse>> me(@AuthenticationPrincipal Long userId) {
		User user = userRepository.findById(userId)
				.orElseThrow(() -> new UserNotFoundException(userId));
		return ResponseEntity.ok(ApiEnvelope.success("OK", toMeResponse(user)));
	}

	/**
	 * PATCH /api/v1/me/profile — partial update of mutable profile fields (API_CONTRACT.md §6.4).
	 *
	 * <p>Permission: {@code woleh.account.profile}. Phase 0: all authenticated users hold this
	 * permission via free tier (PRD §13.1). The {@code @AuthenticationPrincipal} guard on
	 * {@code /api/v1/**} ensures only authenticated calls reach this handler.
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

		return ResponseEntity.ok(ApiEnvelope.success("Profile updated", toMeResponse(user)));
	}

	// ── helpers ──────────────────────────────────────────────────────────────

	private MeResponse toMeResponse(User user) {
		return new MeResponse(
				new MeResponse.Profile(
						String.valueOf(user.getId()),
						user.getPhoneE164(),
						user.getDisplayName()),
				FREE_PERMISSIONS,
				"free",
				FREE_LIMITS,
				NO_SUBSCRIPTION);
	}
}
