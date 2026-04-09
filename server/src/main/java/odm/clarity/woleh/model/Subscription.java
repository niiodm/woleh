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
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

@Entity
@Table(name = "subscriptions")
public class Subscription {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "user_id", nullable = false)
	private User user;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "plan_id", nullable = false)
	private Plan plan;

	@Enumerated(EnumType.STRING)
	@Column(name = "status", nullable = false, length = 20)
	private SubscriptionStatus status;

	@Column(name = "current_period_start", nullable = false)
	private Instant currentPeriodStart;

	@Column(name = "current_period_end", nullable = false)
	private Instant currentPeriodEnd;

	@Column(name = "grace_period_end", nullable = false)
	private Instant gracePeriodEnd;

	@Column(name = "provider_subscription_id", length = 255)
	private String providerSubscriptionId;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "updated_at", nullable = false)
	private Instant updatedAt;

	protected Subscription() {
	}

	public Subscription(User user, Plan plan, SubscriptionStatus status,
			Instant currentPeriodStart, Instant currentPeriodEnd, Instant gracePeriodEnd) {
		this.user = user;
		this.plan = plan;
		this.status = status;
		this.currentPeriodStart = currentPeriodStart;
		this.currentPeriodEnd = currentPeriodEnd;
		this.gracePeriodEnd = gracePeriodEnd;
	}

	@PrePersist
	void onCreate() {
		Instant now = Instant.now();
		createdAt = now;
		updatedAt = now;
	}

	@PreUpdate
	void onUpdate() {
		updatedAt = Instant.now();
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

	public SubscriptionStatus getStatus() {
		return status;
	}

	public void setStatus(SubscriptionStatus status) {
		this.status = status;
	}

	public Instant getCurrentPeriodStart() {
		return currentPeriodStart;
	}

	public Instant getCurrentPeriodEnd() {
		return currentPeriodEnd;
	}

	public void setCurrentPeriodEnd(Instant currentPeriodEnd) {
		this.currentPeriodEnd = currentPeriodEnd;
	}

	public Instant getGracePeriodEnd() {
		return gracePeriodEnd;
	}

	public void setGracePeriodEnd(Instant gracePeriodEnd) {
		this.gracePeriodEnd = gracePeriodEnd;
	}

	public String getProviderSubscriptionId() {
		return providerSubscriptionId;
	}

	public void setProviderSubscriptionId(String providerSubscriptionId) {
		this.providerSubscriptionId = providerSubscriptionId;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public Instant getUpdatedAt() {
		return updatedAt;
	}
}
