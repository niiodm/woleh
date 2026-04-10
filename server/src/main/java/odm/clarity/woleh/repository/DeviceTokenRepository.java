package odm.clarity.woleh.repository;

import java.util.List;
import java.util.Optional;

import odm.clarity.woleh.model.DeviceToken;

import org.springframework.data.jpa.repository.JpaRepository;

public interface DeviceTokenRepository extends JpaRepository<DeviceToken, Long> {

	Optional<DeviceToken> findByUser_IdAndToken(Long userId, String token);

	List<DeviceToken> findAllByUser_Id(Long userId);

	long deleteByUser_IdAndToken(Long userId, String token);
}
