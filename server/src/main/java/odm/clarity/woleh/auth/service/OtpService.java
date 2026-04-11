package odm.clarity.woleh.auth.service;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.List;

import odm.clarity.woleh.common.error.InvalidOtpException;
import odm.clarity.woleh.common.error.RateLimitedException;
import odm.clarity.woleh.config.OtpProperties;
import odm.clarity.woleh.model.OtpChallenge;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.OtpChallengeRepository;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.sms.SmsAdapter;
import odm.clarity.woleh.subscription.SubscriptionService;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OtpService {

	private static final Logger log = LoggerFactory.getLogger(OtpService.class);
	private static final SecureRandom SECURE_RANDOM = new SecureRandom();

	private static final int MAX_VERIFY_ATTEMPTS = 5;

	private final OtpChallengeRepository otpChallengeRepository;
	private final UserRepository userRepository;
	private final PasswordEncoder passwordEncoder;
	private final SmsAdapter smsAdapter;
	private final OtpProperties otpProperties;
	private final SubscriptionService subscriptionService;

	public OtpService(
			OtpChallengeRepository otpChallengeRepository,
			UserRepository userRepository,
			PasswordEncoder passwordEncoder,
			SmsAdapter smsAdapter,
			OtpProperties otpProperties,
			SubscriptionService subscriptionService) {
		this.otpChallengeRepository = otpChallengeRepository;
		this.userRepository = userRepository;
		this.passwordEncoder = passwordEncoder;
		this.smsAdapter = smsAdapter;
		this.otpProperties = otpProperties;
		this.subscriptionService = subscriptionService;
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

	/**
	 * Verify the OTP for a phone number, issue or look up the user, and return the auth result.
	 *
	 * <p>Rules (ADR 0002 + ADR 0003):
	 * <ul>
	 *   <li>The most recent unconsumed challenge is the one in play.</li>
	 *   <li>Expired challenge → 400.</li>
	 *   <li>≥ 5 failed attempts → 400 (challenge is exhausted; caller must re-send).</li>
	 *   <li>Wrong OTP increments {@code attemptCount} and throws 400.</li>
	 *   <li>Correct OTP: mark consumed, look up or create user, return login/signup flow.</li>
	 *   <li>Already-consumed OTP → 400 (idempotency guard per ADR 0003).</li>
	 * </ul>
	 *
	 * @throws InvalidOtpException on any verification failure
	 */
	@Transactional
	public VerifyOtpResult verifyOtp(String phoneE164, String otp) {
		OtpChallenge challenge = resolveActiveChallenge(phoneE164);

		if (!passwordEncoder.matches(otp, challenge.getOtpHash())) {
			challenge.setAttemptCount(challenge.getAttemptCount() + 1);
			otpChallengeRepository.save(challenge);
			throw new InvalidOtpException("Invalid OTP. Please check the code and try again.");
		}

		challenge.setConsumed(true);
		otpChallengeRepository.save(challenge);

		boolean isNewUser = !userRepository.existsByPhoneE164(phoneE164);
		User user = isNewUser
				? userRepository.save(new User(phoneE164))
				: userRepository.findByPhoneE164(phoneE164).orElseThrow();
		if (isNewUser) {
			subscriptionService.activateFreePlanForNewUser(user);
		}

		String flow = isNewUser ? "signup" : "login";
		return new VerifyOtpResult(user.getId(), flow);
	}

	// ── helpers ──────────────────────────────────────────────────────────────

	private OtpChallenge resolveActiveChallenge(String phoneE164) {
		List<OtpChallenge> pending =
				otpChallengeRepository.findByPhoneE164AndConsumedOrderByCreatedAtDesc(phoneE164, false);

		if (pending.isEmpty()) {
			throw new InvalidOtpException("No active OTP found for this number. Please request a new code.");
		}

		OtpChallenge latest = pending.get(0);

		if (latest.getExpiresAt().isBefore(Instant.now())) {
			throw new InvalidOtpException("OTP has expired. Please request a new code.");
		}

		if (latest.getAttemptCount() >= MAX_VERIFY_ATTEMPTS) {
			throw new InvalidOtpException(
					"OTP invalidated after too many failed attempts. Please request a new code.");
		}

		return latest;
	}

	// ─────────────────────────────────────────────────────────────────────────

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
