package odm.clarity.woleh.api;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalManagementPort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.TestPropertySource;

/**
 * With a separate management port, actuator is not served on the main server port — reverse
 * proxies (e.g. Caddy) must not expose metrics on the public API port. Verifies readiness is
 * reachable on the management port without auth (staging Docker/Prometheus use the same split).
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestPropertySource(properties = "management.server.port=0")
class ManagementPortIntegrationTest {

	@Autowired
	private TestRestTemplate restTemplate;

	@LocalManagementPort
	private int managementPort;

	@Test
	void healthReadinessOnManagementPort_returnsUp() {
		String url = "http://127.0.0.1:" + managementPort + "/actuator/health/readiness";
		ResponseEntity<String> response = restTemplate.getForEntity(url, String.class);
		assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
		assertThat(response.getBody()).contains("\"status\":\"UP\"");
	}

}
