package odm.clarity.woleh.ratelimit;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import odm.clarity.woleh.common.error.RateLimitedException;
import odm.clarity.woleh.config.RateLimitProperties;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/** Unit tests for {@link PlaceListRateLimiter} fixed-window logic. */
class RateLimiterTest {

	private PlaceListRateLimiter rateLimiter;

	@BeforeEach
	void setup() {
		rateLimiter = new PlaceListRateLimiter(
				new RateLimitProperties(new RateLimitProperties.PlaceListLimits(3)));
	}

	@Test
	void requestsWithinLimitAllPass() {
		assertThatCode(() -> {
			rateLimiter.checkWatch(1L);
			rateLimiter.checkWatch(1L);
			rateLimiter.checkWatch(1L);
		}).doesNotThrowAnyException();
	}

	@Test
	void requestExceedingLimitThrows() {
		rateLimiter.checkWatch(1L);
		rateLimiter.checkWatch(1L);
		rateLimiter.checkWatch(1L);

		assertThatThrownBy(() -> rateLimiter.checkWatch(1L))
				.isInstanceOf(RateLimitedException.class)
				.hasMessageContaining("Too many requests");
	}

	@Test
	void retryAfterSecondsIsPositive() {
		rateLimiter.checkWatch(1L);
		rateLimiter.checkWatch(1L);
		rateLimiter.checkWatch(1L);

		assertThatThrownBy(() -> rateLimiter.checkWatch(1L))
				.isInstanceOf(RateLimitedException.class)
				.satisfies(ex -> {
					long retryAfter = ((RateLimitedException) ex).getRetryAfterSeconds();
					org.assertj.core.api.Assertions.assertThat(retryAfter).isGreaterThan(0);
				});
	}

	@Test
	void differentUsersAreIsolated() {
		rateLimiter.checkWatch(1L);
		rateLimiter.checkWatch(1L);
		rateLimiter.checkWatch(1L);

		// user 2 should not be affected by user 1's limit
		assertThatCode(() -> rateLimiter.checkWatch(2L)).doesNotThrowAnyException();
	}

	@Test
	void watchAndBroadcastCountsSeparately() {
		rateLimiter.checkWatch(1L);
		rateLimiter.checkWatch(1L);
		rateLimiter.checkWatch(1L);

		// broadcast for the same user uses a separate bucket
		assertThatCode(() -> rateLimiter.checkBroadcast(1L)).doesNotThrowAnyException();
	}

	@Test
	void broadcastLimitIsEnforcedIndependently() {
		rateLimiter.checkBroadcast(1L);
		rateLimiter.checkBroadcast(1L);
		rateLimiter.checkBroadcast(1L);

		assertThatThrownBy(() -> rateLimiter.checkBroadcast(1L))
				.isInstanceOf(RateLimitedException.class);
	}

	@Test
	void windowResetsAfterClear() {
		rateLimiter.checkWatch(1L);
		rateLimiter.checkWatch(1L);
		rateLimiter.checkWatch(1L);
		rateLimiter.clearForTesting();

		// window cleared — should be allowed again
		assertThatCode(() -> {
			rateLimiter.checkWatch(1L);
			rateLimiter.checkWatch(1L);
			rateLimiter.checkWatch(1L);
		}).doesNotThrowAnyException();
	}
}
