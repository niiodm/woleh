package odm.clarity.woleh.api.error;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.common.error.InvalidOtpException;
import odm.clarity.woleh.common.error.PaymentException;
import odm.clarity.woleh.common.error.PermissionDeniedException;
import odm.clarity.woleh.common.error.PlaceLimitExceededException;
import odm.clarity.woleh.common.error.PlaceNameValidationException;
import odm.clarity.woleh.common.error.RateLimitedException;
import odm.clarity.woleh.common.error.UserNotFoundException;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.lang.NonNull;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.servlet.NoHandlerFoundException;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

	@Override
	protected ResponseEntity<Object> handleHttpMessageNotReadable(
			HttpMessageNotReadableException ex,
			@NonNull HttpHeaders headers,
			@NonNull HttpStatusCode status,
			@NonNull WebRequest request) {
		return ResponseEntity.status(HttpStatus.BAD_REQUEST)
				.body(ApiEnvelope.error("Malformed JSON body", "BAD_REQUEST"));
	}

	@Override
	protected ResponseEntity<Object> handleMethodArgumentNotValid(
			MethodArgumentNotValidException ex,
			@NonNull HttpHeaders headers,
			@NonNull HttpStatusCode status,
			@NonNull WebRequest request) {
		String msg = ex.getBindingResult().getFieldErrors().stream()
				.findFirst()
				.map(e -> e.getField() + ": " + e.getDefaultMessage())
				.orElse("Validation failed");
		return ResponseEntity.status(HttpStatus.BAD_REQUEST)
				.body(ApiEnvelope.error(msg, "VALIDATION_ERROR"));
	}

	@Override
	protected ResponseEntity<Object> handleNoHandlerFoundException(
			NoHandlerFoundException ex,
			@NonNull HttpHeaders headers,
			@NonNull HttpStatusCode status,
			@NonNull WebRequest request) {
		return ResponseEntity.status(HttpStatus.NOT_FOUND)
				.body(ApiEnvelope.error("Not found", "NOT_FOUND"));
	}

	@ExceptionHandler(UserNotFoundException.class)
	ResponseEntity<ApiEnvelope<Void>> handleUserNotFound(UserNotFoundException ex) {
		return ResponseEntity.status(HttpStatus.NOT_FOUND)
				.body(ApiEnvelope.error(ex.getMessage(), "NOT_FOUND"));
	}

	@ExceptionHandler(InvalidOtpException.class)
	ResponseEntity<ApiEnvelope<Void>> handleInvalidOtp(InvalidOtpException ex) {
		return ResponseEntity.status(HttpStatus.BAD_REQUEST)
				.body(ApiEnvelope.error(ex.getMessage(), "INVALID_OTP"));
	}

	@ExceptionHandler(RateLimitedException.class)
	ResponseEntity<ApiEnvelope<Void>> handleRateLimited(RateLimitedException ex) {
		var builder = ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS);
		if (ex.getRetryAfterSeconds() > 0) {
			builder.header("Retry-After", String.valueOf(ex.getRetryAfterSeconds()));
		}
		return builder.body(ApiEnvelope.error(ex.getMessage(), "RATE_LIMITED"));
	}

	@ExceptionHandler(PlaceNameValidationException.class)
	ResponseEntity<ApiEnvelope<Void>> handlePlaceNameValidation(PlaceNameValidationException ex) {
		return ResponseEntity.status(HttpStatus.BAD_REQUEST)
				.body(ApiEnvelope.error(ex.getMessage(), "VALIDATION_ERROR"));
	}

	@ExceptionHandler(PermissionDeniedException.class)
	ResponseEntity<ApiEnvelope<Void>> handlePermissionDenied(PermissionDeniedException ex) {
		return ResponseEntity.status(HttpStatus.FORBIDDEN)
				.body(ApiEnvelope.error(ex.getMessage(), "PERMISSION_DENIED"));
	}

	@ExceptionHandler(PlaceLimitExceededException.class)
	ResponseEntity<ApiEnvelope<Void>> handlePlaceLimitExceeded(PlaceLimitExceededException ex) {
		return ResponseEntity.status(HttpStatus.FORBIDDEN)
				.body(ApiEnvelope.error(ex.getMessage(), "OVER_LIMIT"));
	}

	@ExceptionHandler(PaymentException.class)
	ResponseEntity<ApiEnvelope<Void>> handlePayment(PaymentException ex) {
		return ResponseEntity.status(ex.getStatusCode())
				.body(ApiEnvelope.error(ex.getMessage(), "PAYMENT_ERROR"));
	}

	@ExceptionHandler(Exception.class)
	ResponseEntity<ApiEnvelope<Void>> fallback(Exception ex) {
		return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
				.body(ApiEnvelope.error("Unexpected error", "INTERNAL_ERROR"));
	}
}
