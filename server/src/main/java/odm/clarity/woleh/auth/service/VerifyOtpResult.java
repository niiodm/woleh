package odm.clarity.woleh.auth.service;

/**
 * Internal result from {@link OtpService#verifyOtp}, carrying what the controller
 * needs to build the JWT and response without exposing domain objects.
 *
 * @param userId authenticated (or newly created) user id
 * @param flow   {@code "login"} or {@code "signup"}
 */
public record VerifyOtpResult(long userId, String flow) {
}
