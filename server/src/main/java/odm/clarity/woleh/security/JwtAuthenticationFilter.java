package odm.clarity.woleh.security;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Collections;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import odm.clarity.woleh.api.dto.ApiEnvelope;

import org.slf4j.MDC;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.fasterxml.jackson.databind.ObjectMapper;

import io.jsonwebtoken.JwtException;

@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

	private final JwtService jwtService;
	private final ObjectMapper objectMapper;

	public JwtAuthenticationFilter(JwtService jwtService, ObjectMapper objectMapper) {
		this.jwtService = jwtService;
		this.objectMapper = objectMapper;
	}

	@Override
	protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
			throws ServletException, IOException {
		try {
			String header = request.getHeader(HttpHeaders.AUTHORIZATION);
			if (header != null && header.startsWith("Bearer ")) {
				String token = header.substring(7).trim();
				if (!token.isEmpty()) {
					try {
						long userId = jwtService.parseUserId(token);
						MDC.put("userId", String.valueOf(userId));
						var auth = new UsernamePasswordAuthenticationToken(
								userId,
								null,
								Collections.singletonList(new SimpleGrantedAuthority("ROLE_USER")));
						auth.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
						SecurityContextHolder.getContext().setAuthentication(auth);
					}
					catch (JwtException | IllegalArgumentException e) {
						SecurityContextHolder.clearContext();
						writeUnauthorized(response, "Invalid or expired token");
						return;
					}
				}
			}
			filterChain.doFilter(request, response);
		}
		finally {
			MDC.remove("userId");
		}
	}

	private void writeUnauthorized(HttpServletResponse response, String message) throws IOException {
		response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
		response.setContentType(MediaType.APPLICATION_JSON_VALUE);
		response.setCharacterEncoding(StandardCharsets.UTF_8.name());
		objectMapper.writeValue(response.getOutputStream(), ApiEnvelope.error(message, "UNAUTHORIZED"));
	}
}
