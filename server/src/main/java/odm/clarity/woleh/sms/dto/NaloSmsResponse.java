package odm.clarity.woleh.sms.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Response DTO for NALO SMS API (same fields and status semantics as bus_finder).
 */
public record NaloSmsResponse(
		@JsonProperty("status") String status,
		@JsonProperty("job_id") String jobId,
		@JsonProperty("msisdn") String msisdn) {

	public boolean isSuccess() {
		return "1701".equals(status);
	}

	public String getErrorDescription() {
		if (isSuccess()) {
			return null;
		}
		if (status == null) {
			return "Unknown error (no status)";
		}
		return switch (status) {
			case "1702" -> "Invalid URL Error - One of the parameters was not provided or left blank";
			case "1703" -> "Invalid value in username or password field";
			case "1704" -> "Invalid value in 'type' field";
			case "1705" -> "Invalid Message";
			case "1706" -> "Invalid Destination";
			case "1707" -> "Invalid Source (Sender)";
			case "1708" -> "Invalid value for 'dlr' field";
			case "1709" -> "User validation failed";
			case "1710" -> "Internal Error";
			case "1025" -> "Insufficient Credit User";
			case "1026" -> "Insufficient Credit Reseller";
			default -> "Unknown error code: " + status;
		};
	}
}
