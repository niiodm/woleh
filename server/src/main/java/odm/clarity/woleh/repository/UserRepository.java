package odm.clarity.woleh.repository;

import java.util.Optional;

import odm.clarity.woleh.model.User;

import org.springframework.data.jpa.repository.JpaRepository;

public interface UserRepository extends JpaRepository<User, Long> {

	Optional<User> findByPhoneE164(String phoneE164);

	boolean existsByPhoneE164(String phoneE164);
}
