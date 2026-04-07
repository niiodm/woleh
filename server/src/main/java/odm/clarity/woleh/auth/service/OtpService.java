package odm.clarity.woleh.auth.service;

import java.security.SecureRandom;
import java.time.Instant;

import odm.clarity.woleh.common.error.RateLimitedException;
import odm.clarity.woleh.config.OtpProperties;
import odm.clarity.woleh.model.OtpChallenge;
import odm.clarity.woleh.repository.OtpChallengeRepository;
import odm.clarity.woleh.sms.SmsAdapter;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OtpService {

	private static final Logger log = LoggerFactory.getLogger(OtpService.class);
	private static final SecureRandom SECURE_RANDOM = new SecureRandom();

	private final OtpChallengeRepository otpChallengeRepository;
	private final PasswordEncoder passwordEncoder;
	private final SmsAdapter smsAdapter;
	private final OtpProperties otpProperties;

	public OtpService(
			OtpChallengeRepository otpChallengeRepository,
			PasswordEncoder passwordEncoder,
			SmsAdapter smsAdapter,
			OtpProperties otpProperties) {
		this.otpChallengeRepository = otpChallengeRepository;
		this.passwordEncoder = passwordEncoder;
		this.smsAdapter = smsAdapter;
		this.otpProperties = otpProperties;
	}

	/**
	 * Issue a new OTP challenge for the given phone number.
	 *
	 * @return the persisted {@link OtpChallenge}
	 * @throws RateLimitedException if the number has exceeded the send rate limit (ADR 0002)
	 */
	@Transactional
	public OtpChallenge issueOtp(String phoneE164) {
		enforceRateLimit(phoneE164);

		String otp = generateOtp();
		String otpHash = passwordEncoder.encode(otp);
		Instant expiresAt = Instant.now().plus(otpProperties.ttl());

		OtpChallenge challenge = otpChallengeRepository.save(
				new OtpChallenge(phoneE164, otpHash, expiresAt));

		if (otpProperties.devLogOtp()) {
			// Intentionally INFO so it appears in dev console; guarded by config flag.
			log.info("[DEV] OTP for {}: {}", phoneE164, otp);
		}

		smsAdapter.sendOtp(phoneE164, otp);

		return challenge;
	}

	// ── helpers ──────────────────────────────────────────────────────────────

	private void enforceRateLimit(String phoneE164) {
		Instant windowStart = Instant.now().minus(otpProperties.rateLimitWindow());
		long recent = otpChallengeRepository.countByPhoneE164AndCreatedAtAfter(phoneE164, windowStart);
		if (recent >= otpProperties.rateLimitMaxSends()) {
			throw new RateLimitedException(
					"Too many OTP requests for this number. Please try again later.");
		}
	}

	private static String generateOtp() {
		int otp = SECURE_RANDOM.nextInt(1_000_000);
		return String.format("%06d", otp);
	}
}
