package odm.clarity.woleh.ws;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

/**
 * Registers the transit WebSocket endpoint and enables the heartbeat scheduler.
 *
 * <p>The endpoint path is {@code /ws/v1/transit}.
 * Authentication is delegated entirely to {@link JwtHandshakeInterceptor};
 * Spring Security is configured to {@code permitAll()} on {@code /ws/**} so the
 * upgrade HTTP request reaches the interceptor rather than being blocked by the
 * {@code JwtAuthenticationFilter}.
 */
@Configuration
@EnableWebSocket
@EnableScheduling
public class WsConfig implements WebSocketConfigurer {

	private final TransitWebSocketHandler transitHandler;
	private final JwtHandshakeInterceptor jwtInterceptor;

	public WsConfig(TransitWebSocketHandler transitHandler, JwtHandshakeInterceptor jwtInterceptor) {
		this.transitHandler = transitHandler;
		this.jwtInterceptor = jwtInterceptor;
	}

	@Override
	public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
		registry.addHandler(transitHandler, "/ws/v1/transit")
				.addInterceptors(jwtInterceptor)
				.setAllowedOriginPatterns("*");
	}
}
