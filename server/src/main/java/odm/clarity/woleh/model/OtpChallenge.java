package odm.clarity.woleh.model;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "otp_challenges")
public class OtpChallenge {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@Column(name = "phone_e164", nullable = false, length = 20)
	private String phoneE164;

	@Column(name = "otp_hash", nullable = false, length = 255)
	private String otpHash;

	@Column(name = "expires_at", nullable = false)
	private Instant expiresAt;

	@Column(name = "attempt_count", nullable = false)
	private int attemptCount;

	@Column(name = "consumed", nullable = false)
	private boolean consumed;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	protected OtpChallenge() {
	}

	public OtpChallenge(String phoneE164, String otpHash, Instant expiresAt) {
		this.phoneE164 = phoneE164;
		this.otpHash = otpHash;
		this.expiresAt = expiresAt;
	}

	@PrePersist
	void onCreate() {
		createdAt = Instant.now();
	}

	public Long getId() {
		return id;
	}

	public String getPhoneE164() {
		return phoneE164;
	}

	public String getOtpHash() {
		return otpHash;
	}

	public Instant getExpiresAt() {
		return expiresAt;
	}

	public int getAttemptCount() {
		return attemptCount;
	}

	public void setAttemptCount(int attemptCount) {
		this.attemptCount = attemptCount;
	}

	public boolean isConsumed() {
		return consumed;
	}

	public void setConsumed(boolean consumed) {
		this.consumed = consumed;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}
}
