package odm.clarity.woleh.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public record SendOtpRequest(
		@NotBlank(message = "must not be blank")
		@Pattern(regexp = "\\+[1-9]\\d{6,14}", message = "must be a valid E.164 phone number (e.g. +447911123456)")
		String phoneE164) {
}
