package odm.clarity.woleh.common.error;

/**
 * Thrown when an authenticated user's current entitlements do not include
 * the permission required by a service operation.
 * Maps to HTTP 403 in {@code GlobalExceptionHandler}.
 */
public class PermissionDeniedException extends RuntimeException {

	private final String permission;

	public PermissionDeniedException(String permission) {
		super("Permission required: " + permission);
		this.permission = permission;
	}

	public String getPermission() {
		return permission;
	}
}
