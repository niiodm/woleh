package odm.clarity.woleh.auth.dto;

/**
 * Response body for {@code POST /api/v1/auth/verify-otp}.
 * Per API_CONTRACT.md §6.2.
 *
 * @param flow {@code "login"} if an existing account was authenticated;
 *             {@code "signup"} if a new account was created by this verification.
 */
public record VerifyOtpResponse(
		String accessToken,
		String tokenType,
		long expiresInSeconds,
		String userId,
		String flow) {
}
