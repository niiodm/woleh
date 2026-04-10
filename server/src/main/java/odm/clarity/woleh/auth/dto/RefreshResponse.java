package odm.clarity.woleh.auth.dto;

/**
 * Response body for {@code POST /api/v1/auth/refresh}.
 *
 * @param expiresIn seconds until the new access token expires
 */
public record RefreshResponse(String accessToken, String refreshToken, long expiresIn) {}
