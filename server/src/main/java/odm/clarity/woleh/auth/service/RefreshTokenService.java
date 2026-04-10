package odm.clarity.woleh.auth.service;

import java.time.Instant;

import odm.clarity.woleh.common.error.InvalidRefreshTokenException;
import odm.clarity.woleh.config.WolehJwtProperties;
import odm.clarity.woleh.model.RefreshToken;
import odm.clarity.woleh.repository.RefreshTokenRepository;
import odm.clarity.woleh.security.JwtService;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Manages the lifecycle of opaque refresh tokens (FR-A2).
 *
 * <p>Tokens are stored only as SHA-256 hex digests; the raw value is returned once at
 * issuance and never persisted. Rotation invalidates the presented token by setting
 * {@code revoked = true} and issuing a fresh token pair.
 */
@Service
@Transactional
public class RefreshTokenService {

	/**
	 * Carries the result of a successful token rotation or initial issuance so the
	 * controller can build the response without knowing the internal representation.
	 */
	public record IssuedTokens(String accessToken, String refreshToken, long accessExpiresInSeconds) {}

	private final RefreshTokenRepository repository;
	private final JwtService jwtService;
	private final WolehJwtProperties jwtProps;

	public RefreshTokenService(
			RefreshTokenRepository repository,
			JwtService jwtService,
			WolehJwtProperties jwtProps) {
		this.repository = repository;
		this.jwtService = jwtService;
		this.jwtProps = jwtProps;
	}

	/**
	 * Generates a new refresh token for the given user, stores its hash, and returns
	 * the raw (unhashed) token to be sent to the client.
	 */
	public String issue(Long userId) {
		String raw = jwtService.generateRefreshToken();
		String hash = jwtService.hashToken(raw);
		Instant expiresAt = Instant.now().plus(jwtProps.refreshTokenTtl());
		repository.save(new RefreshToken(userId, hash, expiresAt));
		return raw;
	}

	/**
	 * Validates the presented refresh token, marks it revoked, and issues a new access
	 * + refresh token pair (token rotation).
	 *
	 * @throws InvalidRefreshTokenException if the token is unknown, revoked, or expired
	 */
	public IssuedTokens rotate(String rawToken) {
		String hash = jwtService.hashToken(rawToken);
		RefreshToken stored = repository.findByTokenHash(hash)
				.orElseThrow(() -> new InvalidRefreshTokenException("Refresh token not found"));

		if (stored.isRevoked()) {
			throw new InvalidRefreshTokenException("Refresh token has been revoked");
		}
		if (stored.isExpired()) {
			throw new InvalidRefreshTokenException("Refresh token has expired");
		}

		Long userId = stored.getUserId();
		stored.revoke();

		Instant now = Instant.now();
		String newAccessToken = jwtService.createAccessToken(userId, now);
		String newRawRefreshToken = issue(userId);

		return new IssuedTokens(
				newAccessToken,
				newRawRefreshToken,
				jwtProps.accessTokenTtl().toSeconds());
	}

	/**
	 * Revokes all refresh tokens for the given user (used by logout).
	 * The user is identified from the provided raw token so no access token is required.
	 * Returns silently if the token is unknown (logout is idempotent).
	 */
	public void revokeByRawToken(String rawToken) {
		String hash = jwtService.hashToken(rawToken);
		repository.findByTokenHash(hash)
				.ifPresent(t -> repository.deleteAllByUserId(t.getUserId()));
	}
}
