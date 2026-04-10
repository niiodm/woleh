package odm.clarity.woleh.model;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * Persisted refresh-token record.
 *
 * <p>The raw opaque token is never stored here — only its SHA-256 hex digest.
 * On rotation the old row is marked {@code revoked = true} and a new row is inserted,
 * giving a full audit trail.
 */
@Entity
@Table(name = "refresh_tokens")
public class RefreshToken {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@Column(name = "user_id", nullable = false)
	private Long userId;

	@Column(name = "token_hash", nullable = false, unique = true, length = 64)
	private String tokenHash;

	@Column(name = "expires_at", nullable = false)
	private Instant expiresAt;

	@Column(name = "revoked", nullable = false)
	private boolean revoked;

	@Column(name = "created_at", nullable = false, updatable = false)
	private Instant createdAt;

	protected RefreshToken() {}

	public RefreshToken(Long userId, String tokenHash, Instant expiresAt) {
		this.userId = userId;
		this.tokenHash = tokenHash;
		this.expiresAt = expiresAt;
		this.revoked = false;
		this.createdAt = Instant.now();
	}

	public Long getId() { return id; }
	public Long getUserId() { return userId; }
	public String getTokenHash() { return tokenHash; }
	public Instant getExpiresAt() { return expiresAt; }
	public boolean isRevoked() { return revoked; }
	public Instant getCreatedAt() { return createdAt; }

	public boolean isExpired() { return Instant.now().isAfter(expiresAt); }

	public void revoke() { this.revoked = true; }
}
