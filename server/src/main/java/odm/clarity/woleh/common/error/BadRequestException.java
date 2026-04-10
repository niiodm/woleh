package odm.clarity.woleh.common.error;

/**
 * Maps to HTTP 400 with {@code VALIDATION_ERROR} in {@code GlobalExceptionHandler}.
 */
public class BadRequestException extends RuntimeException {

	public BadRequestException(String message) {
		super(message);
	}
}
