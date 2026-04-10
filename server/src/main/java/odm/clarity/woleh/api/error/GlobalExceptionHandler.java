package odm.clarity.woleh.api.error;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

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

	private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

	private final Counter counter4xx;
	private final Counter counter5xx;

	public GlobalExceptionHandler(MeterRegistry meterRegistry) {
		super();
		this.counter4xx = Counter.builder("woleh.api.errors")
				.tag("status_class", "4xx")
				.description("API responses in the 4xx client-error range")
				.register(meterRegistry);
		this.counter5xx = Counter.builder("woleh.api.errors")
				.tag("status_class", "5xx")
				.description("API responses in the 5xx server-error range")
				.register(meterRegistry);
	}

	@Override
	protected ResponseEntity<Object> handleHttpMessageNotReadable(
			HttpMessageNotReadableException ex,
			@NonNull HttpHeaders headers,
			@NonNull HttpStatusCode status,
			@NonNull WebRequest request) {
		counter4xx.increment();
		log.debug("Bad request — malformed JSON: {}", ex.getMessage());
		return ResponseEntity.status(HttpStatus.BAD_REQUEST)
				.body(ApiEnvelope.error("Malformed JSON body", "BAD_REQUEST"));
	}

	@Override
	protected ResponseEntity<Object> handleMethodArgumentNotValid(
			MethodArgumentNotValidException ex,
			@NonNull HttpHeaders headers,
			@NonNull HttpStatusCode status,
			@NonNull WebRequest request) {
		counter4xx.increment();
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
		counter4xx.increment();
		return ResponseEntity.status(HttpStatus.NOT_FOUND)
				.body(ApiEnvelope.error("Not found", "NOT_FOUND"));
	}

	@ExceptionHandler(UserNotFoundException.class)
	ResponseEntity<ApiEnvelope<Void>> handleUserNotFound(UserNotFoundException ex) {
		counter4xx.increment();
		return ResponseEntity.status(HttpStatus.NOT_FOUND)
				.body(ApiEnvelope.error(ex.getMessage(), "NOT_FOUND"));
	}

	@ExceptionHandler(InvalidOtpException.class)
	ResponseEntity<ApiEnvelope<Void>> handleInvalidOtp(InvalidOtpException ex) {
		counter4xx.increment();
		return ResponseEntity.status(HttpStatus.BAD_REQUEST)
				.body(ApiEnvelope.error(ex.getMessage(), "INVALID_OTP"));
	}

	@ExceptionHandler(RateLimitedException.class)
	ResponseEntity<ApiEnvelope<Void>> handleRateLimited(RateLimitedException ex) {
		counter4xx.increment();
		log.debug("Rate limit exceeded: {}", ex.getMessage());
		var builder = ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS);
		if (ex.getRetryAfterSeconds() > 0) {
			builder.header("Retry-After", String.valueOf(ex.getRetryAfterSeconds()));
		}
		return builder.body(ApiEnvelope.error(ex.getMessage(), "RATE_LIMITED"));
	}

	@ExceptionHandler(PlaceNameValidationException.class)
	ResponseEntity<ApiEnvelope<Void>> handlePlaceNameValidation(PlaceNameValidationException ex) {
		counter4xx.increment();
		return ResponseEntity.status(HttpStatus.BAD_REQUEST)
				.body(ApiEnvelope.error(ex.getMessage(), "VALIDATION_ERROR"));
	}

	@ExceptionHandler(PermissionDeniedException.class)
	ResponseEntity<ApiEnvelope<Void>> handlePermissionDenied(PermissionDeniedException ex) {
		counter4xx.increment();
		return ResponseEntity.status(HttpStatus.FORBIDDEN)
				.body(ApiEnvelope.error(ex.getMessage(), "PERMISSION_DENIED"));
	}

	@ExceptionHandler(PlaceLimitExceededException.class)
	ResponseEntity<ApiEnvelope<Void>> handlePlaceLimitExceeded(PlaceLimitExceededException ex) {
		counter4xx.increment();
		return ResponseEntity.status(HttpStatus.FORBIDDEN)
				.body(ApiEnvelope.error(ex.getMessage(), "OVER_LIMIT"));
	}

	@ExceptionHandler(PaymentException.class)
	ResponseEntity<ApiEnvelope<Void>> handlePayment(PaymentException ex) {
		if (ex.getStatusCode() >= 500) {
			counter5xx.increment();
			log.error("Payment provider error (5xx): {}", ex.getMessage(), ex);
		}
		else {
			counter4xx.increment();
			log.debug("Payment client error (4xx): {}", ex.getMessage());
		}
		return ResponseEntity.status(ex.getStatusCode())
				.body(ApiEnvelope.error(ex.getMessage(), "PAYMENT_ERROR"));
	}

	@ExceptionHandler(Exception.class)
	ResponseEntity<ApiEnvelope<Void>> fallback(Exception ex) {
		counter5xx.increment();
		log.error("Unhandled exception", ex);
		return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
				.body(ApiEnvelope.error("Unexpected error", "INTERNAL_ERROR"));
	}
}
