package odm.clarity.woleh.security;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Date;
import java.util.HexFormat;

import javax.crypto.SecretKey;

import odm.clarity.woleh.config.WolehJwtProperties;

import org.springframework.stereotype.Service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

/**
 * Issues and validates access tokens; generates and hashes opaque refresh tokens.
 */
@Service
public class JwtService {

	private static final SecureRandom SECURE_RANDOM = new SecureRandom();

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

	/** Generates a cryptographically random 32-byte opaque refresh token (64 hex chars). */
	public String generateRefreshToken() {
		byte[] bytes = new byte[32];
		SECURE_RANDOM.nextBytes(bytes);
		return HexFormat.of().formatHex(bytes);
	}

	/**
	 * Returns the SHA-256 hex digest of the raw token.
	 * Always store and compare hashes, never the raw value.
	 */
	public String hashToken(String raw) {
		try {
			MessageDigest digest = MessageDigest.getInstance("SHA-256");
			byte[] hash = digest.digest(raw.getBytes(StandardCharsets.UTF_8));
			return HexFormat.of().formatHex(hash);
		}
		catch (NoSuchAlgorithmException e) {
			throw new IllegalStateException("SHA-256 not available", e);
		}
	}

	/** Issues a signed access token. */
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
