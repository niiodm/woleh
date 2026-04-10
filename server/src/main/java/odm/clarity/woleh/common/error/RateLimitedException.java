package odm.clarity.woleh.common.error;

/**
 * Thrown when a caller exceeds a rate limit.
 *
 * <p>Set {@code retryAfterSeconds} to a positive value when the retry window is known
 * (the handler will emit a {@code Retry-After} response header). Pass {@code -1} when
 * the window cannot be easily computed (e.g. DB-backed OTP limits).
 */
public class RateLimitedException extends RuntimeException {

	private final long retryAfterSeconds;

	/** Use when the retry-after time is not known (omits {@code Retry-After} header). */
	public RateLimitedException(String message) {
		super(message);
		this.retryAfterSeconds = -1;
	}

	/** Use when the retry-after time is known; value is included in the response header. */
	public RateLimitedException(String message, long retryAfterSeconds) {
		super(message);
		this.retryAfterSeconds = retryAfterSeconds;
	}

	/** Seconds until the rate-limit window resets, or {@code -1} if unknown. */
	public long getRetryAfterSeconds() {
		return retryAfterSeconds;
	}
}
