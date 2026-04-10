package odm.clarity.woleh.common.error;

/**
 * Thrown when a refresh token is not found, has been revoked, or has expired.
 * Maps to HTTP 401 in {@link odm.clarity.woleh.api.error.GlobalExceptionHandler}.
 */
public class InvalidRefreshTokenException extends RuntimeException {

	public InvalidRefreshTokenException(String message) {
		super(message);
	}
}
