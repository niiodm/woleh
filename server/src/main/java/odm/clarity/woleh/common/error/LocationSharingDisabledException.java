package odm.clarity.woleh.common.error;

/**
 * Thrown when the client POSTs a location fix but the user has not enabled sharing.
 * Maps to HTTP 403 with code {@code LOCATION_SHARING_OFF} in {@code GlobalExceptionHandler}.
 */
public class LocationSharingDisabledException extends RuntimeException {

	public LocationSharingDisabledException() {
		super("Location sharing is off. Enable it before publishing your position.");
	}
}
