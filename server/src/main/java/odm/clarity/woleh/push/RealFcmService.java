package odm.clarity.woleh.push;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

import odm.clarity.woleh.model.DeviceToken;
import odm.clarity.woleh.repository.DeviceTokenRepository;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.auth.oauth2.GoogleCredentials;

/**
 * FCM HTTP v1 sender using a service-account JSON key. Requires
 * {@code woleh.push.fcm.project-id} and {@code woleh.push.fcm.service-account-json-path}.
 */
@Service
@ConditionalOnProperty(name = "woleh.push.enabled", havingValue = "true")
public class RealFcmService implements FcmService {

	private static final Logger log = LoggerFactory.getLogger(RealFcmService.class);
	private static final String FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

	private final DeviceTokenRepository deviceTokenRepository;
	private final ObjectMapper objectMapper;
	private final RestClient restClient;
	private final String projectId;
	private final String serviceAccountJsonPath;

	public RealFcmService(
			DeviceTokenRepository deviceTokenRepository,
			ObjectMapper objectMapper,
			@Value("${woleh.push.fcm.project-id:}") String projectId,
			@Value("${woleh.push.fcm.service-account-json-path:}") String serviceAccountJsonPath) {
		this.deviceTokenRepository = deviceTokenRepository;
		this.objectMapper = objectMapper;
		this.restClient = RestClient.create();
		this.projectId = projectId;
		this.serviceAccountJsonPath = serviceAccountJsonPath;
	}

	@Override
	public void sendNotification(long userId, String title, String body, Map<String, String> data) {
		if (projectId.isBlank() || serviceAccountJsonPath.isBlank()) {
			log.warn("woleh.push.enabled=true but woleh.push.fcm.project-id or service-account-json-path is blank — skipping push for userId={}",
					userId);
			return;
		}

		var registrations = deviceTokenRepository.findAllByUser_Id(userId);
		if (registrations.isEmpty()) {
			log.debug("RealFcmService: no device tokens for userId={}", userId);
			return;
		}

		String accessToken;
		try {
			accessToken = fetchAccessToken();
		}
		catch (IOException e) {
			log.error("RealFcmService: failed to obtain OAuth token for FCM", e);
			return;
		}

		for (DeviceToken registration : registrations) {
			try {
				sendToDevice(accessToken, registration.getToken(), title, body, data);
			}
			catch (RestClientResponseException e) {
				log.warn("RealFcmService: FCM request failed for userId={} status={} body={}",
						userId, e.getStatusCode().value(), e.getResponseBodyAsString());
			}
			catch (Exception e) {
				log.warn("RealFcmService: unexpected error sending to userId={}", userId, e);
			}
		}
	}

	private String fetchAccessToken() throws IOException {
		try (var in = Files.newInputStream(Path.of(serviceAccountJsonPath))) {
			GoogleCredentials credentials = GoogleCredentials.fromStream(in).createScoped(FCM_SCOPE);
			credentials.refreshIfExpired();
			return credentials.getAccessToken().getTokenValue();
		}
	}

	private void sendToDevice(String accessToken, String deviceToken, String title, String body,
			Map<String, String> data) throws Exception {

		var notification = Map.of("title", title, "body", body);
		var dataStrings = new HashMap<String, String>();
		if (data != null) {
			data.forEach((k, v) -> dataStrings.put(k, v == null ? "" : v));
		}

		var message = new HashMap<String, Object>();
		message.put("token", deviceToken);
		message.put("notification", notification);
		if (!dataStrings.isEmpty()) {
			message.put("data", dataStrings);
		}

		String json = objectMapper.writeValueAsString(Map.of("message", message));
		String uri = "https://fcm.googleapis.com/v1/projects/" + projectId + "/messages:send";

		restClient.post()
				.uri(uri)
				.header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
				.contentType(MediaType.APPLICATION_JSON)
				.body(json)
				.retrieve()
				.toBodilessEntity();
	}
}
