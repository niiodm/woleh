package odm.clarity.woleh.security;

import java.io.IOException;
import java.util.UUID;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Servlet filter that assigns a correlation ID to every inbound request.
 *
 * <p>The ID is taken from the {@code X-Request-Id} request header when present; otherwise a
 * random UUID is generated. The resolved ID is:
 * <ul>
 *   <li>stored in {@link MDC} as {@code requestId} so every log line for the request carries it;
 *   <li>echoed back to the caller as the {@code X-Request-Id} response header.
 * </ul>
 *
 * <p>Runs at {@code HIGHEST_PRECEDENCE + 1} so it wraps the JWT and Spring Security filters,
 * guaranteeing the MDC value is set before any other filter logs.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 1)
public class CorrelationIdFilter extends OncePerRequestFilter {

	static final String REQUEST_ID_HEADER = "X-Request-Id";
	static final String MDC_KEY = "requestId";

	@Override
	protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
			FilterChain filterChain) throws ServletException, IOException {
		String requestId = request.getHeader(REQUEST_ID_HEADER);
		if (requestId == null || requestId.isBlank()) {
			requestId = UUID.randomUUID().toString();
		}
		MDC.put(MDC_KEY, requestId);
		response.addHeader(REQUEST_ID_HEADER, requestId);
		try {
			filterChain.doFilter(request, response);
		}
		finally {
			MDC.remove(MDC_KEY);
		}
	}
}
