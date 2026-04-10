package odm.clarity.woleh.auth.dto;

/** Request body for {@code POST /api/v1/auth/logout}. {@code refreshToken} is optional. */
public record LogoutRequest(String refreshToken) {}
