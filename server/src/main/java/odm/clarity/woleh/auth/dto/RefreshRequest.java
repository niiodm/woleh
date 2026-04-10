package odm.clarity.woleh.auth.dto;

import jakarta.validation.constraints.NotBlank;

/** Request body for {@code POST /api/v1/auth/refresh}. */
public record RefreshRequest(@NotBlank String refreshToken) {}
