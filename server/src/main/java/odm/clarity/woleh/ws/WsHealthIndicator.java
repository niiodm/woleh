package odm.clarity.woleh.ws;

import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.stereotype.Component;

/**
 * Actuator health component for the WebSocket subsystem.
 *
 * <p>Reports the active session count so operators can quickly see how many clients
 * are connected. The component is always {@code UP} — individual session errors are
 * handled by {@link WsSessionRegistry} (dead sessions are evicted on send failure).
 */
@Component("ws")
public class WsHealthIndicator implements HealthIndicator {

	private final WsSessionRegistry sessionRegistry;

	public WsHealthIndicator(WsSessionRegistry sessionRegistry) {
		this.sessionRegistry = sessionRegistry;
	}

	@Override
	public Health health() {
		return Health.up()
				.withDetail("activeSessions", sessionRegistry.sessionCount())
				.build();
	}
}
