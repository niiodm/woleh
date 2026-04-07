package odm.clarity.woleh.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record VerifyOtpRequest(
		@NotBlank(message = "must not be blank")
		@Pattern(regexp = "\\+[1-9]\\d{6,14}", message = "must be a valid E.164 phone number")
		String phoneE164,

		@NotBlank(message = "must not be blank")
		@Pattern(regexp = "\\d{6}", message = "must be exactly 6 digits")
		@Size(min = 6, max = 6, message = "must be exactly 6 digits")
		String otp) {
}
