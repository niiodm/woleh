package odm.clarity.woleh.ratelimit;

import java.time.Duration;
import java.util.concurrent.ConcurrentHashMap;

import odm.clarity.woleh.common.error.RateLimitedException;
import odm.clarity.woleh.config.RateLimitProperties;

import org.springframework.stereotype.Component;

/**
 * Per-user fixed-window rate limiter for place-list write operations.
 *
 * <p>Uses a {@link ConcurrentHashMap} keyed by {@code "userId:listType"}; each entry holds
 * a two-element {@code long[]} of {@code [windowStartMs, requestCount]}.
 * {@link ConcurrentHashMap#compute} provides atomic bucket-level updates, making the
 * implementation safe for concurrent requests without global locking.
 *
 * <p><strong>Single-node only.</strong> This implementation stores state in the JVM heap.
 * For multi-instance deployments, replace with a Redis-backed sliding-window limiter or
 * delegate to an API gateway — requires an ADR before making that change.
 */
@Component
public class PlaceListRateLimiter {

	private static final Duration WINDOW = Duration.ofMinutes(1);

	private final int maxRequestsPerMinute;
	private final ConcurrentHashMap<String, long[]> windows = new ConcurrentHashMap<>();

	public PlaceListRateLimiter(RateLimitProperties props) {
		this.maxRequestsPerMinute = props.placeList().requestsPerMinute();
	}

	/** Enforce the rate limit for a watch-list PUT. */
	public void checkWatch(Long userId) {
		check(userId + ":watch");
	}

	/** Enforce the rate limit for a broadcast-list PUT. */
	public void checkBroadcast(Long userId) {
		check(userId + ":broadcast");
	}

	// ── internals ─────────────────────────────────────────────────────────────

	private void check(String key) {
		long nowMs = System.currentTimeMillis();
		long windowMs = WINDOW.toMillis();

		long[] state = windows.compute(key, (k, s) -> {
			if (s == null || nowMs - s[0] >= windowMs) {
				return new long[] { nowMs, 1 };
			}
			s[1]++;
			return s;
		});

		if (state[1] > maxRequestsPerMinute) {
			long elapsed = nowMs - state[0];
			long retryAfterSeconds = Math.max(1, (windowMs - elapsed) / 1000 + 1);
			throw new RateLimitedException(
					"Too many requests. Please try again later.", retryAfterSeconds);
		}
	}

	/** Clear all rate-limit state. Exposed for testing only. */
	public void clearForTesting() {
		windows.clear();
	}
}
