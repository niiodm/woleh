package odm.clarity.woleh.security;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;

import javax.crypto.SecretKey;

import odm.clarity.woleh.config.WolehJwtProperties;

import org.springframework.stereotype.Service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

/**
 * Validates access tokens (step 3.3) and issues them (used by verify-otp in step 3.5).
 */
@Service
public class JwtService {

	private final WolehJwtProperties props;
	private final SecretKey key;

	public JwtService(WolehJwtProperties props) {
		this.props = props;
		this.key = signingKey(props.secret());
	}

	private static SecretKey signingKey(String secret) {
		byte[] bytes = secret.getBytes(StandardCharsets.UTF_8);
		if (bytes.length < 32) {
			throw new IllegalStateException("JWT secret must be at least 256 bits (32 bytes) for HS256");
		}
		return Keys.hmacShaKeyFor(bytes);
	}

	public long parseUserId(String token) throws JwtException {
		Claims claims = Jwts.parser()
				.verifyWith(key)
				.requireIssuer(props.issuer())
				.build()
				.parseSignedClaims(token)
				.getPayload();
		return Long.parseLong(claims.getSubject());
	}

	/** Issue an access token (verify-otp will call this in step 3.5). */
	public String createAccessToken(long userId, Instant issuedAt) {
		Instant exp = issuedAt.plus(props.accessTokenTtl());
		return Jwts.builder()
				.subject(String.valueOf(userId))
				.issuer(props.issuer())
				.issuedAt(Date.from(issuedAt))
				.expiration(Date.from(exp))
				.signWith(key)
				.compact();
	}
}
