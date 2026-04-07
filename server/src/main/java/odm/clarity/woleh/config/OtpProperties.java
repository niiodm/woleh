package odm.clarity.woleh.config;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * OTP policy from ADR 0002.
 *
 * <ul>
 *   <li>{@code ttl} – challenge lifetime; default 5 minutes</li>
 *   <li>{@code rateLimitWindow} – rolling window for rate-limit counting; default 1 hour</li>
 *   <li>{@code rateLimitMaxSends} – max successful sends per number per window; default 3</li>
 *   <li>{@code devLogOtp} – when {@code true} echoes the plaintext OTP to the console; never enable in production</li>
 * </ul>
 */
@ConfigurationProperties(prefix = "woleh.otp")
public record OtpProperties(
		Duration ttl,
		Duration rateLimitWindow,
		int rateLimitMaxSends,
		boolean devLogOtp) {

	public OtpProperties {
		if (ttl == null) ttl = Duration.ofMinutes(5);
		if (rateLimitWindow == null) rateLimitWindow = Duration.ofHours(1);
		if (rateLimitMaxSends <= 0) rateLimitMaxSends = 3;
	}
}
