package odm.clarity.woleh.repository;

import java.util.Optional;

import odm.clarity.woleh.model.RefreshToken;

import org.springframework.data.jpa.repository.JpaRepository;

public interface RefreshTokenRepository extends JpaRepository<RefreshToken, Long> {

	Optional<RefreshToken> findByTokenHash(String tokenHash);

	void deleteAllByUserId(Long userId);
}
