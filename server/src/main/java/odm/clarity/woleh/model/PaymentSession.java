package odm.clarity.woleh.model;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "payment_sessions")
public class PaymentSession {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "user_id", nullable = false)
	private User user;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "plan_id", nullable = false)
	private Plan plan;

	@Column(name = "session_id", nullable = false, unique = true, length = 255)
	private String sessionId;

	@Column(name = "provider_reference", length = 255)
	private String providerReference;

	@Enumerated(EnumType.STRING)
	@Column(name = "status", nullable = false, length = 20)
	private PaymentSessionStatus status;

	@Column(name = "checkout_url", nullable = false, columnDefinition = "TEXT")
	private String checkoutUrl;

	@Column(name = "expires_at", nullable = false)
	private Instant expiresAt;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	protected PaymentSession() {
	}

	public PaymentSession(User user, Plan plan, String sessionId, String checkoutUrl, Instant expiresAt) {
		this.user = user;
		this.plan = plan;
		this.sessionId = sessionId;
		this.status = PaymentSessionStatus.PENDING;
		this.checkoutUrl = checkoutUrl;
		this.expiresAt = expiresAt;
	}

	@PrePersist
	void onCreate() {
		createdAt = Instant.now();
	}

	public Long getId() {
		return id;
	}

	public User getUser() {
		return user;
	}

	public Plan getPlan() {
		return plan;
	}

	public String getSessionId() {
		return sessionId;
	}

	public String getProviderReference() {
		return providerReference;
	}

	public void setProviderReference(String providerReference) {
		this.providerReference = providerReference;
	}

	public PaymentSessionStatus getStatus() {
		return status;
	}

	public void setStatus(PaymentSessionStatus status) {
		this.status = status;
	}

	public String getCheckoutUrl() {
		return checkoutUrl;
	}

	public Instant getExpiresAt() {
		return expiresAt;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}
}
