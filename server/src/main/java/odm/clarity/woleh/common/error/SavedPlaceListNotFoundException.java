package odm.clarity.woleh.common.error;

/**
 * Thrown when a saved place list id or share token does not exist (or is not visible).
 * Maps to HTTP 404 in {@link odm.clarity.woleh.api.error.GlobalExceptionHandler}.
 */
public class SavedPlaceListNotFoundException extends RuntimeException {

	public SavedPlaceListNotFoundException() {
		super("Saved place list not found");
	}
}
