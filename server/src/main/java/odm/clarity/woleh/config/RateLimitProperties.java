package odm.clarity.woleh.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Rate-limit policy for high-frequency write endpoints.
 *
 * <ul>
 *   <li>{@code placeList.requestsPerMinute} – max PUT requests per user per minute for
 *       watch/broadcast lists; default 10 (configurable via {@code PLACE_LIST_RPM} env var).</li>
 *   <li>{@code locationPublish.minIntervalMillis} – minimum spacing between
 *       {@code POST /api/v1/me/location} per user; default 1000.</li>
 * </ul>
 *
 * <p>The current implementation uses a per-JVM fixed-window counter backed by a
 * {@code ConcurrentHashMap}. For multi-instance deployments, replace with a Redis-backed
 * sliding-window limiter or delegate to an API gateway — requires ADR before that change.
 */
@ConfigurationProperties(prefix = "woleh.ratelimit")
public record RateLimitProperties(PlaceListLimits placeList, LocationPublishLimits locationPublish) {

	public record PlaceListLimits(int requestsPerMinute) {

		public PlaceListLimits {
			if (requestsPerMinute <= 0) requestsPerMinute = 10;
		}
	}

	public record LocationPublishLimits(int minIntervalMillis) {

		public LocationPublishLimits {
			if (minIntervalMillis <= 0) minIntervalMillis = 1000;
		}
	}

	public RateLimitProperties {
		if (placeList == null) placeList = new PlaceListLimits(10);
		if (locationPublish == null) locationPublish = new LocationPublishLimits(1000);
	}
}
