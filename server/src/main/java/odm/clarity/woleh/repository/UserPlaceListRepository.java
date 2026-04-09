package odm.clarity.woleh.repository;

import java.util.List;
import java.util.Optional;

import odm.clarity.woleh.model.PlaceListType;
import odm.clarity.woleh.model.UserPlaceList;

import org.springframework.data.jpa.repository.JpaRepository;

public interface UserPlaceListRepository extends JpaRepository<UserPlaceList, Long> {

	/**
	 * Returns the place list for a specific user and list type, or empty if none exists yet.
	 * Used by GET and PUT handlers to load the current list before upsert.
	 */
	Optional<UserPlaceList> findByUser_IdAndListType(Long userId, PlaceListType listType);

	/**
	 * Returns all place lists of a given type across all users.
	 * Used by {@code MatchingService} to scan for intersection candidates when a
	 * complementary list is updated.
	 */
	List<UserPlaceList> findAllByListType(PlaceListType listType);
}
