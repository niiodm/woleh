package odm.clarity.woleh.common.error;

/**
 * Thrown when a place-name list PUT would exceed the user's tier limit.
 * Maps to HTTP 403 with code {@code OVER_LIMIT} in {@code GlobalExceptionHandler}.
 */
public class PlaceLimitExceededException extends RuntimeException {

	private final int limit;

	public PlaceLimitExceededException(String listType, int limit) {
		super("Exceeded " + listType + " list limit of " + limit);
		this.limit = limit;
	}

	public int getLimit() {
		return limit;
	}
}
