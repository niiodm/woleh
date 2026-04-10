package odm.clarity.woleh.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Rate-limit policy for high-frequency write endpoints.
 *
 * <ul>
 *   <li>{@code placeList.requestsPerMinute} – max PUT requests per user per minute for
 *       watch/broadcast lists; default 10 (configurable via {@code PLACE_LIST_RPM} env var).</li>
 * </ul>
 *
 * <p>The current implementation uses a per-JVM fixed-window counter backed by a
 * {@code ConcurrentHashMap}. For multi-instance deployments, replace with a Redis-backed
 * sliding-window limiter or delegate to an API gateway — requires ADR before that change.
 */
@ConfigurationProperties(prefix = "woleh.ratelimit")
public record RateLimitProperties(PlaceListLimits placeList) {

	public record PlaceListLimits(int requestsPerMinute) {

		public PlaceListLimits {
			if (requestsPerMinute <= 0) requestsPerMinute = 10;
		}
	}

	public RateLimitProperties {
		if (placeList == null) placeList = new PlaceListLimits(10);
	}
}
