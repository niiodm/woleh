package odm.clarity.woleh.auth;

import java.time.Instant;

import jakarta.validation.Valid;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.auth.dto.SendOtpRequest;
import odm.clarity.woleh.auth.dto.SendOtpResponse;
import odm.clarity.woleh.auth.dto.VerifyOtpRequest;
import odm.clarity.woleh.auth.dto.VerifyOtpResponse;
import odm.clarity.woleh.auth.service.OtpService;
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

	public AuthController(
			OtpService otpService,
			OtpProperties otpProperties,
			JwtService jwtService,
			WolehJwtProperties jwtProperties) {
		this.otpService = otpService;
		this.otpProperties = otpProperties;
		this.jwtService = jwtService;
		this.jwtProperties = jwtProperties;
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

	/** POST /api/v1/auth/verify-otp — verify OTP, issue JWT, determine login/signup flow (ADR 0002, ADR 0003). */
	@PostMapping("/verify-otp")
	ResponseEntity<ApiEnvelope<VerifyOtpResponse>> verifyOtp(
			@RequestBody @Valid VerifyOtpRequest request) {

		VerifyOtpResult result = otpService.verifyOtp(request.phoneE164(), request.otp());

		Instant now = Instant.now();
		String token = jwtService.createAccessToken(result.userId(), now);
		long expiresInSeconds = jwtProperties.accessTokenTtl().toSeconds();

		return ResponseEntity.ok(ApiEnvelope.success(
				"OTP verified",
				new VerifyOtpResponse(
						token,
						"Bearer",
						expiresInSeconds,
						String.valueOf(result.userId()),
						result.flow())));
	}
}
