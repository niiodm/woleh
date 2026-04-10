package odm.clarity.woleh.ratelimit;

import java.util.concurrent.ConcurrentHashMap;

import odm.clarity.woleh.common.error.RateLimitedException;
import odm.clarity.woleh.config.RateLimitProperties;

import org.springframework.stereotype.Component;

/**
 * Per-user minimum interval between location publishes ({@code POST /api/v1/me/location}).
 *
 * <p><strong>Single-node only</strong> — same caveats as {@link PlaceListRateLimiter}.
 */
@Component
public class LocationPublishRateLimiter {

	private final long minIntervalMs;
	private final ConcurrentHashMap<Long, Long> lastPublishEpochMs = new ConcurrentHashMap<>();

	public LocationPublishRateLimiter(RateLimitProperties props) {
		this.minIntervalMs = props.locationPublish().minIntervalMillis();
	}

	public void check(Long userId) {
		long now = System.currentTimeMillis();
		lastPublishEpochMs.compute(userId, (id, last) -> {
			if (last == null || now - last >= minIntervalMs) {
				return now;
			}
			long waitMs = minIntervalMs - (now - last);
			long retryAfterSeconds = Math.max(1, (waitMs + 999) / 1000);
			throw new RateLimitedException(
					"Too many location updates. Please try again later.", retryAfterSeconds);
		});
	}

	/** Clears all state. For tests only. */
	public void clearForTesting() {
		lastPublishEpochMs.clear();
	}
}
