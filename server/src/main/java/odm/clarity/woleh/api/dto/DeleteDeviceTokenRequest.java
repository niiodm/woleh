package odm.clarity.woleh.api.dto;

import jakarta.validation.constraints.NotBlank;

public record DeleteDeviceTokenRequest(@NotBlank String token) {
}
