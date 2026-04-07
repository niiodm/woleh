package odm.clarity.woleh.auth;

import jakarta.validation.Valid;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.auth.dto.SendOtpRequest;
import odm.clarity.woleh.auth.dto.SendOtpResponse;
import odm.clarity.woleh.auth.service.OtpService;
import odm.clarity.woleh.config.OtpProperties;
import odm.clarity.woleh.model.OtpChallenge;

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

	public AuthController(OtpService otpService, OtpProperties otpProperties) {
		this.otpService = otpService;
		this.otpProperties = otpProperties;
	}

	/** POST /api/v1/auth/send-otp — issue a 6-digit OTP challenge (ADR 0002). */
	@PostMapping("/send-otp")
	ResponseEntity<ApiEnvelope<SendOtpResponse>> sendOtp(
			@RequestBody @Valid SendOtpRequest request) {

		OtpChallenge challenge = otpService.issueOtp(request.phoneE164());
		long expiresInSeconds = otpProperties.ttl().toSeconds();

		return ResponseEntity.ok(ApiEnvelope.success(
				"OTP sent",
				new SendOtpResponse(expiresInSeconds)));
	}
}
