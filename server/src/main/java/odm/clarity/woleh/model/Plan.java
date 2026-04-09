package odm.clarity.woleh.model;

import java.util.List;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "plans")
public class Plan {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@Column(name = "plan_id", nullable = false, unique = true, length = 100)
	private String planId;

	@Column(name = "display_name", nullable = false, length = 255)
	private String displayName;

	@Column(name = "permissions_granted", nullable = false, columnDefinition = "TEXT")
	@Convert(converter = StringListConverter.class)
	private List<String> permissionsGranted;

	@Column(name = "price_amount_minor", nullable = false)
	private int priceAmountMinor;

	@Column(name = "price_currency", nullable = false, length = 3)
	private String priceCurrency;

	@Column(name = "place_watch_max", nullable = false)
	private int placeWatchMax;

	@Column(name = "place_broadcast_max", nullable = false)
	private int placeBroadcastMax;

	@Column(name = "active", nullable = false)
	private boolean active;

	protected Plan() {
	}

	public Plan(String planId, String displayName, List<String> permissionsGranted,
			int priceAmountMinor, String priceCurrency,
			int placeWatchMax, int placeBroadcastMax, boolean active) {
		this.planId = planId;
		this.displayName = displayName;
		this.permissionsGranted = permissionsGranted;
		this.priceAmountMinor = priceAmountMinor;
		this.priceCurrency = priceCurrency;
		this.placeWatchMax = placeWatchMax;
		this.placeBroadcastMax = placeBroadcastMax;
		this.active = active;
	}

	public Long getId() {
		return id;
	}

	public String getPlanId() {
		return planId;
	}

	public String getDisplayName() {
		return displayName;
	}

	public List<String> getPermissionsGranted() {
		return permissionsGranted;
	}

	public int getPriceAmountMinor() {
		return priceAmountMinor;
	}

	public String getPriceCurrency() {
		return priceCurrency;
	}

	public int getPlaceWatchMax() {
		return placeWatchMax;
	}

	public int getPlaceBroadcastMax() {
		return placeBroadcastMax;
	}

	public boolean isActive() {
		return active;
	}

	public void setActive(boolean active) {
		this.active = active;
	}

	public void setPriceAmountMinor(int priceAmountMinor) {
		this.priceAmountMinor = priceAmountMinor;
	}
}
