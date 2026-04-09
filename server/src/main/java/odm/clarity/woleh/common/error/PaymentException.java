package odm.clarity.woleh.common.error;

/**
 * Thrown for payment business-logic errors (unknown plan, provider failure, etc.).
 * The HTTP status code is carried by the exception so callers can control
 * whether the error is a 400 Bad Request or a 409 Conflict.
 */
public class PaymentException extends RuntimeException {

	private final int statusCode;

	public PaymentException(String message, int statusCode) {
		super(message);
		this.statusCode = statusCode;
	}

	public int getStatusCode() {
		return statusCode;
	}
}
