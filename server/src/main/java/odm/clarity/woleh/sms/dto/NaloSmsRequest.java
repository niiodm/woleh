package odm.clarity.woleh.sms.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Request body for NALO SMS API (same schema as bus_finder).
 *
 * <p>Endpoint: POST {@code https://sms.nalosolutions.com/smsbackend/Resl_Nalo/send-message/}
 */
public record NaloSmsRequest(
		@JsonProperty("key") String key,
		@JsonProperty("msisdn") String msisdn,
		@JsonProperty("message") String message,
		@JsonProperty("sender_id") String senderId) {}
