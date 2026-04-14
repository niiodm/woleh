package odm.clarity.woleh.repository;

import java.util.List;
import java.util.Optional;

import odm.clarity.woleh.model.UserSavedPlaceList;

import org.springframework.data.jpa.repository.JpaRepository;

public interface UserSavedPlaceListRepository extends JpaRepository<UserSavedPlaceList, Long> {

	List<UserSavedPlaceList> findByUser_IdOrderByUpdatedAtDesc(Long userId);

	Optional<UserSavedPlaceList> findByShareToken(String shareToken);

	long countByUser_Id(Long userId);

	Optional<UserSavedPlaceList> findByIdAndUser_Id(Long id, Long userId);

	boolean existsByShareToken(String shareToken);
}
