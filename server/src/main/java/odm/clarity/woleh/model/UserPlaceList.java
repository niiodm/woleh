package odm.clarity.woleh.model;

import java.time.Instant;
import java.util.Collections;
import java.util.List;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
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
import jakarta.persistence.UniqueConstraint;

/**
 * Stores a single place-name list (watch or broadcast) for a user.
 *
 * <p>Both the user-entered display form and the pre-normalized form are persisted:
 * <ul>
 *   <li>{@code displayNames} — returned to the client as-entered.</li>
 *   <li>{@code normalizedNames} — used for matching queries (no re-normalization at read time).</li>
 * </ul>
 *
 * <p>At most one row exists per (user, listType) pair (enforced by DB unique constraint
 * and upsert logic in the service layer).
 */
@Entity
@Table(
		name = "user_place_lists",
		uniqueConstraints = @UniqueConstraint(
				name = "uq_user_place_lists_user_list",
				columnNames = { "user_id", "list_type" }))
public class UserPlaceList {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "user_id", nullable = false)
	private User user;

	@Enumerated(EnumType.STRING)
	@Column(name = "list_type", nullable = false, length = 10)
	private PlaceListType listType;

	/** User-entered strings — stored for display, returned to client unchanged. */
	@Convert(converter = StringListConverter.class)
	@Column(name = "display_names", nullable = false, columnDefinition = "TEXT")
	private List<String> displayNames = Collections.emptyList();

	/** Normalized strings — stored for matching; produced by {@code PlaceNameNormalizer}. */
	@Convert(converter = StringListConverter.class)
	@Column(name = "normalized_names", nullable = false, columnDefinition = "TEXT")
	private List<String> normalizedNames = Collections.emptyList();

	@Column(name = "updated_at", nullable = false)
	private Instant updatedAt;

	protected UserPlaceList() {
	}

	public UserPlaceList(User user, PlaceListType listType,
			List<String> displayNames, List<String> normalizedNames) {
		this.user = user;
		this.listType = listType;
		this.displayNames = displayNames;
		this.normalizedNames = normalizedNames;
	}

	@PrePersist
	@PreUpdate
	void onSave() {
		updatedAt = Instant.now();
	}

	public Long getId() {
		return id;
	}

	public User getUser() {
		return user;
	}

	public PlaceListType getListType() {
		return listType;
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

	public Instant getUpdatedAt() {
		return updatedAt;
	}
}
