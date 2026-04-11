package odm.clarity.woleh.sms;

import odm.clarity.woleh.sms.dto.NaloSmsRequest;
import odm.clarity.woleh.sms.dto.NaloSmsResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

/**
 * NALO SMS integration (same API and behavior as bus_finder {@code NaloSmsService}).
 *
 * <p>Enable with {@code sms.provider=nalo} and set {@code sms.nalo.api-key} (and optional URL / sender).
 *
 * <p>On HTTP or API errors, logs and returns without throwing so the OTP challenge flow still completes
 * (matches bus_finder).
 */
@Service
@ConditionalOnProperty(name = "sms.provider", havingValue = "nalo")
public class NaloSmsAdapter implements SmsAdapter {

	private static final Logger log = LoggerFactory.getLogger(NaloSmsAdapter.class);

	private final RestTemplate smsRestTemplate;

	@Value("${sms.nalo.api-url}")
	private String apiUrl;

	@Value("${sms.nalo.api-key}")
	private String apiKey;

	@Value("${sms.nalo.sender-id:NALO}")
	private String senderId;

	@Value("${sms.nalo.otp-message-template:Your Woleh OTP is: {}. Valid for 5 minutes.}")
	private String otpMessageTemplate;

	public NaloSmsAdapter(RestTemplate smsRestTemplate) {
		this.smsRestTemplate = smsRestTemplate;
	}

	@Override
	public void sendOtp(String phoneE164, String otp) {
		log.info("Sending OTP via NALO SMS to phone: {}", phoneE164);

		try {
			String normalizedPhone = PhoneNumberUtil.normalizeToNaloFormat(phoneE164);

			if (!PhoneNumberUtil.isValidNaloFormat(normalizedPhone)) {
				log.error("Invalid phone number format after normalization: {} → {}",
						phoneE164, normalizedPhone);
				return;
			}

			String message = otpMessageTemplate.replace("{}", otp);

			NaloSmsRequest request = new NaloSmsRequest(apiKey, normalizedPhone, message, senderId);

			HttpHeaders headers = new HttpHeaders();
			headers.setContentType(MediaType.APPLICATION_JSON);
			HttpEntity<NaloSmsRequest> entity = new HttpEntity<>(request, headers);

			log.debug("Calling NALO SMS API: {} with phone: {}", apiUrl, normalizedPhone);
			ResponseEntity<NaloSmsResponse> response = smsRestTemplate.postForEntity(
					apiUrl,
					entity,
					NaloSmsResponse.class);

			NaloSmsResponse responseBody = response.getBody();
			if (responseBody != null) {
				if (responseBody.isSuccess()) {
					log.info("OTP sent successfully via NALO SMS to {} (Job ID: {})",
							normalizedPhone, responseBody.jobId());
				} else {
					String errorDesc = responseBody.getErrorDescription();
					if ("1025".equals(responseBody.status()) || "1026".equals(responseBody.status())) {
						log.error("NALO SMS API error - Insufficient credit: {} - {}",
								responseBody.status(), errorDesc);
					} else {
						log.warn("NALO SMS API error: {} - {} (Phone: {})",
								responseBody.status(), errorDesc, normalizedPhone);
					}
				}
			} else {
				log.warn("NALO SMS API returned empty response body for phone: {}", normalizedPhone);
			}
		} catch (RestClientException e) {
			log.error("Failed to send OTP via NALO SMS API for phone {}: {}",
					phoneE164, e.getMessage(), e);
		} catch (Exception e) {
			log.error("Unexpected error sending OTP via NALO SMS for phone {}: {}",
					phoneE164, e.getMessage(), e);
		}
	}
}
