package odm.clarity.woleh.api;

import static org.assertj.core.api.Assertions.assertThat;

import io.micrometer.core.instrument.MeterRegistry;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * Smoke tests that verify all custom Micrometer meters are registered when the
 * application context starts (Phase 3, Step 2.2).
 */
@SpringBootTest
class MetricsIntegrationTest {

	@Autowired
	MeterRegistry registry;

	@Test
	void wsSessionsActive_gaugeRegistered() {
		assertThat(registry.find("woleh.ws.sessions.active").gauge()).isNotNull();
	}

	@Test
	void placeListPutWatch_counterRegistered() {
		assertThat(registry.find("woleh.place.list.put").tag("list_type", "watch").counter()).isNotNull();
	}

	@Test
	void placeListPutBroadcast_counterRegistered() {
		assertThat(registry.find("woleh.place.list.put").tag("list_type", "broadcast").counter()).isNotNull();
	}

	@Test
	void matchEvaluation_timerRegistered() {
		assertThat(registry.find("woleh.match.evaluation").timer()).isNotNull();
	}

	@Test
	void apiErrors4xx_counterRegistered() {
		assertThat(registry.find("woleh.api.errors").tag("status_class", "4xx").counter()).isNotNull();
	}

	@Test
	void apiErrors5xx_counterRegistered() {
		assertThat(registry.find("woleh.api.errors").tag("status_class", "5xx").counter()).isNotNull();
	}
}
