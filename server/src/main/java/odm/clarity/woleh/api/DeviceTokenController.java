package odm.clarity.woleh.api;

import jakarta.validation.Valid;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.api.dto.DeleteDeviceTokenRequest;
import odm.clarity.woleh.api.dto.RegisterDeviceTokenRequest;
import odm.clarity.woleh.common.error.BadRequestException;
import odm.clarity.woleh.common.error.PermissionDeniedException;
import odm.clarity.woleh.model.DevicePlatform;
import odm.clarity.woleh.push.DeviceTokenService;
import odm.clarity.woleh.subscription.EntitlementService;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
public class DeviceTokenController {

	private static final String PROFILE_PERMISSION = "woleh.account.profile";

	private final EntitlementService entitlementService;
	private final DeviceTokenService deviceTokenService;

	public DeviceTokenController(EntitlementService entitlementService, DeviceTokenService deviceTokenService) {
		this.entitlementService = entitlementService;
		this.deviceTokenService = deviceTokenService;
	}

	@PostMapping("/me/device-token")
	ResponseEntity<ApiEnvelope<Void>> register(
			@AuthenticationPrincipal Long userId,
			@RequestBody @Valid RegisterDeviceTokenRequest request) {
		requireProfilePermission(userId);
		DevicePlatform platform = parsePlatform(request.platform());
		deviceTokenService.upsert(userId, request.token(), platform);
		return ResponseEntity.ok(ApiEnvelope.success("Device token registered", null));
	}

	@DeleteMapping("/me/device-token")
	ResponseEntity<ApiEnvelope<Void>> delete(
			@AuthenticationPrincipal Long userId,
			@RequestBody @Valid DeleteDeviceTokenRequest request) {
		requireProfilePermission(userId);
		deviceTokenService.deleteByUserAndToken(userId, request.token());
		return ResponseEntity.ok(ApiEnvelope.success("Device token removed", null));
	}

	private void requireProfilePermission(Long userId) {
		var entitlements = entitlementService.computeEntitlements(userId);
		if (!entitlements.permissions().contains(PROFILE_PERMISSION)) {
			throw new PermissionDeniedException(PROFILE_PERMISSION);
		}
	}

	private static DevicePlatform parsePlatform(String raw) {
		try {
			return DevicePlatform.valueOf(raw.trim().toLowerCase());
		}
		catch (IllegalArgumentException e) {
			throw new BadRequestException("platform must be android or ios");
		}
	}
}
