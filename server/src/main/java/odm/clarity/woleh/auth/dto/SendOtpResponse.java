package odm.clarity.woleh.auth.dto;

/**
 * Response body for {@code POST /api/v1/auth/send-otp}.
 * Per API_CONTRACT.md §6.1: {@code expiresInSeconds} is the challenge TTL in seconds.
 */
public record SendOtpResponse(long expiresInSeconds) {
}
