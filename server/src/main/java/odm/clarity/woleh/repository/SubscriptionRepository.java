package odm.clarity.woleh.repository;

import java.util.Optional;

import odm.clarity.woleh.model.Subscription;
import odm.clarity.woleh.model.SubscriptionStatus;

import org.springframework.data.jpa.repository.JpaRepository;

public interface SubscriptionRepository extends JpaRepository<Subscription, Long> {

	/**
	 * Returns the most recent subscription for a user with the given status,
	 * ordered by {@code currentPeriodEnd} descending so the latest active period wins.
	 */
	Optional<Subscription> findTopByUser_IdAndStatusOrderByCurrentPeriodEndDesc(
			Long userId, SubscriptionStatus status);
}
