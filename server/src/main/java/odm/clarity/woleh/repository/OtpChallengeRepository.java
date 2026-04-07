package odm.clarity.woleh.repository;

import java.util.List;

import odm.clarity.woleh.model.OtpChallenge;

import org.springframework.data.jpa.repository.JpaRepository;

public interface OtpChallengeRepository extends JpaRepository<OtpChallenge, Long> {

	List<OtpChallenge> findByPhoneE164AndConsumedOrderByCreatedAtDesc(String phoneE164, boolean consumed);
}
