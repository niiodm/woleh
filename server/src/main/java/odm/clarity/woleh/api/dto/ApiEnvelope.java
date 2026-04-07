package odm.clarity.woleh.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * REST envelope per {@code API_CONTRACT.md} §2.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ApiEnvelope<T>(String result, String message, T data, String code) {

	public static <T> ApiEnvelope<T> success(String message, T data) {
		return new ApiEnvelope<>("SUCCESS", message, data, null);
	}

	public static ApiEnvelope<Void> error(String message, String code) {
		return new ApiEnvelope<>("ERROR", message, null, code);
	}
}
