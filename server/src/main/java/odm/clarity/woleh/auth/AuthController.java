package odm.clarity.woleh.auth;

import java.time.Instant;

import jakarta.validation.Valid;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.auth.dto.LogoutRequest;
import odm.clarity.woleh.auth.dto.RefreshRequest;
import odm.clarity.woleh.auth.dto.RefreshResponse;
import odm.clarity.woleh.auth.dto.SendOtpRequest;
import odm.clarity.woleh.auth.dto.SendOtpResponse;
import odm.clarity.woleh.auth.dto.VerifyOtpRequest;
import odm.clarity.woleh.auth.dto.VerifyOtpResponse;
import odm.clarity.woleh.auth.service.OtpService;
import odm.clarity.woleh.auth.service.RefreshTokenService;
import odm.clarity.woleh.auth.service.VerifyOtpResult;
import odm.clarity.woleh.config.OtpProperties;
import odm.clarity.woleh.config.WolehJwtProperties;
import odm.clarity.woleh.security.JwtService;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

	private final OtpService otpService;
	private final OtpProperties otpProperties;
	private final JwtService jwtService;
	private final WolehJwtProperties jwtProperties;
	private final RefreshTokenService refreshTokenService;

	public AuthController(
			OtpService otpService,
			OtpProperties otpProperties,
			JwtService jwtService,
			WolehJwtProperties jwtProperties,
			RefreshTokenService refreshTokenService) {
		this.otpService = otpService;
		this.otpProperties = otpProperties;
		this.jwtService = jwtService;
		this.jwtProperties = jwtProperties;
		this.refreshTokenService = refreshTokenService;
	}

	/** POST /api/v1/auth/send-otp — issue a 6-digit OTP challenge (ADR 0002). */
	@PostMapping("/send-otp")
	ResponseEntity<ApiEnvelope<SendOtpResponse>> sendOtp(
			@RequestBody @Valid SendOtpRequest request) {

		otpService.issueOtp(request.phoneE164());
		long expiresInSeconds = otpProperties.ttl().toSeconds();

		return ResponseEntity.ok(ApiEnvelope.success(
				"OTP sent",
				new SendOtpResponse(expiresInSeconds)));
	}

	/** POST /api/v1/auth/verify-otp — verify OTP, issue access + refresh tokens (ADR 0002, ADR 0003, FR-A2). */
	@PostMapping("/verify-otp")
	ResponseEntity<ApiEnvelope<VerifyOtpResponse>> verifyOtp(
			@RequestBody @Valid VerifyOtpRequest request) {

		VerifyOtpResult result = otpService.verifyOtp(request.phoneE164(), request.otp());

		Instant now = Instant.now();
		String accessToken = jwtService.createAccessToken(result.userId(), now);
		String refreshToken = refreshTokenService.issue(result.userId());
		long expiresInSeconds = jwtProperties.accessTokenTtl().toSeconds();

		return ResponseEntity.ok(ApiEnvelope.success(
				"OTP verified",
				new VerifyOtpResponse(
						accessToken,
						"Bearer",
						expiresInSeconds,
						String.valueOf(result.userId()),
						result.flow(),
						refreshToken)));
	}

	/** POST /api/v1/auth/refresh — rotate a refresh token and issue a new access + refresh token pair (FR-A2). */
	@PostMapping("/refresh")
	ResponseEntity<ApiEnvelope<RefreshResponse>> refresh(
			@RequestBody @Valid RefreshRequest request) {

		RefreshTokenService.IssuedTokens tokens = refreshTokenService.rotate(request.refreshToken());
		return ResponseEntity.ok(ApiEnvelope.success(
				"Token refreshed",
				new RefreshResponse(tokens.accessToken(), tokens.refreshToken(), tokens.accessExpiresInSeconds())));
	}

	/** POST /api/v1/auth/logout — revoke all refresh tokens for the token's owner (FR-A2). */
	@PostMapping("/logout")
	ResponseEntity<ApiEnvelope<Void>> logout(
			@RequestBody(required = false) LogoutRequest request) {

		if (request != null && request.refreshToken() != null && !request.refreshToken().isBlank()) {
			refreshTokenService.revokeByRawToken(request.refreshToken());
		}
		return ResponseEntity.ok(ApiEnvelope.success("Logged out", null));
	}
}
