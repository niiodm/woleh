package odm.clarity.woleh.common.error;

public class UserNotFoundException extends RuntimeException {

	public UserNotFoundException(long userId) {
		super("User not found: " + userId);
	}
}
