package odm.clarity.woleh.model;

import java.time.Instant;
import java.util.Collections;
import java.util.List;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

/**
 * A user-owned template of place names, persisted for reuse and shareable via {@link #shareToken}.
 *
 * <p>Display and normalized forms follow the same JSON-array convention as {@link UserPlaceList}.
 */
@Entity
@Table(
		name = "user_saved_place_lists",
		uniqueConstraints = @UniqueConstraint(
				name = "uq_user_saved_place_lists_share_token",
				columnNames = { "share_token" }))
public class UserSavedPlaceList {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "user_id", nullable = false)
	private User user;

	@Column(name = "user_id", insertable = false, updatable = false)
	private Long userId;

	@Column(name = "title", length = 255)
	private String title;

	@Column(name = "share_token", nullable = false, length = 64)
	private String shareToken;

	@Convert(converter = StringListConverter.class)
	@Column(name = "display_names", nullable = false, columnDefinition = "TEXT")
	private List<String> displayNames = Collections.emptyList();

	@Convert(converter = StringListConverter.class)
	@Column(name = "normalized_names", nullable = false, columnDefinition = "TEXT")
	private List<String> normalizedNames = Collections.emptyList();

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "updated_at", nullable = false)
	private Instant updatedAt;

	protected UserSavedPlaceList() {
	}

	public UserSavedPlaceList(User user, String title, String shareToken,
			List<String> displayNames, List<String> normalizedNames) {
		this.user = user;
		this.userId = user.getId();
		this.title = title;
		this.shareToken = shareToken;
		this.displayNames = displayNames;
		this.normalizedNames = normalizedNames;
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

	public Long getUserId() {
		return userId;
	}

	public String getTitle() {
		return title;
	}

	public void setTitle(String title) {
		this.title = title;
	}

	public String getShareToken() {
		return shareToken;
	}

	public List<String> getDisplayNames() {
		return displayNames;
	}

	public void setDisplayNames(List<String> displayNames) {
		this.displayNames = displayNames;
	}

	public List<String> getNormalizedNames() {
		return normalizedNames;
	}

	public void setNormalizedNames(List<String> normalizedNames) {
		this.normalizedNames = normalizedNames;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public Instant getUpdatedAt() {
		return updatedAt;
	}
}
