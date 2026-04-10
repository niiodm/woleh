package odm.clarity.woleh.api.dto;

import jakarta.validation.constraints.NotBlank;

public record RegisterDeviceTokenRequest(
		@NotBlank String token,
		@NotBlank String platform) {
}
