package odm.clarity.woleh.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Verifies that {@code CorrelationIdFilter} attaches and echoes the {@code X-Request-Id} header
 * for every request (Phase 3, Step 2.3).
 */
@SpringBootTest
@AutoConfigureMockMvc
class CorrelationIdFilterIntegrationTest {

	@Autowired
	MockMvc mockMvc;

	@Test
	void request_withoutRequestId_generatesAndEchoes() throws Exception {
		mockMvc.perform(get("/actuator/health"))
				.andExpect(status().isOk())
				.andExpect(header().exists("X-Request-Id"))
				.andExpect(header().string("X-Request-Id",
						org.hamcrest.Matchers.matchesPattern(
								"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")));
	}

	@Test
	void request_withCustomRequestId_echosItBack() throws Exception {
		String customId = "test-correlation-id-abc123";
		mockMvc.perform(get("/actuator/health")
				.header("X-Request-Id", customId))
				.andExpect(status().isOk())
				.andExpect(header().string("X-Request-Id", customId));
	}
}
