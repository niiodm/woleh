package odm.clarity.woleh.repository;

import java.util.Optional;

import odm.clarity.woleh.model.PaymentSession;
import odm.clarity.woleh.model.PaymentSessionStatus;

import org.springframework.data.jpa.repository.JpaRepository;

public interface PaymentSessionRepository extends JpaRepository<PaymentSession, Long> {

	Optional<PaymentSession> findBySessionId(String sessionId);

	Optional<PaymentSession> findByProviderReference(String providerReference);

	/**
	 * Finds an existing pending checkout session for a user + plan combination,
	 * used to return an existing session rather than creating a duplicate (idempotency).
	 */
	Optional<PaymentSession> findTopByUser_IdAndPlan_PlanIdAndStatusOrderByCreatedAtDesc(
			Long userId, String planId, PaymentSessionStatus status);
}
