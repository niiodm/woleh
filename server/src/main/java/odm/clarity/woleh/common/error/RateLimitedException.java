package odm.clarity.woleh.common.error;

public class RateLimitedException extends RuntimeException {

	public RateLimitedException(String message) {
		super(message);
	}
}
