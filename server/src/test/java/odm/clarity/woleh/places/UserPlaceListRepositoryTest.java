package odm.clarity.woleh.places;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Optional;

import odm.clarity.woleh.model.PlaceListType;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.model.UserPlaceList;
import odm.clarity.woleh.repository.UserPlaceListRepository;
import odm.clarity.woleh.repository.UserRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

import jakarta.persistence.EntityManager;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class UserPlaceListRepositoryTest {

	@Autowired
	UserPlaceListRepository placeListRepository;

	@Autowired
	UserRepository userRepository;

	@Autowired
	EntityManager entityManager;

	private User userA;
	private User userB;

	@BeforeEach
	void setUp() {
		placeListRepository.deleteAll();
		userA = userRepository.save(new User("+233241000011"));
		userB = userRepository.save(new User("+233241000012"));
	}

	// ── findByUser_IdAndListType ──────────────────────────────────────────

	@Test
	void findByUserAndListType_watchList_roundTrip() {
		List<String> display = List.of("Accra Central", "Circle");
		List<String> normalized = List.of("accra central", "circle");

		placeListRepository.save(new UserPlaceList(userA, PlaceListType.WATCH, display, normalized));
		entityManager.flush();
		entityManager.clear();

		Optional<UserPlaceList> found = placeListRepository
				.findByUser_IdAndListType(userA.getId(), PlaceListType.WATCH);

		assertThat(found).isPresent();
		assertThat(found.get().getDisplayNames()).containsExactlyElementsOf(display);
		assertThat(found.get().getNormalizedNames()).containsExactlyElementsOf(normalized);
		assertThat(found.get().getListType()).isEqualTo(PlaceListType.WATCH);
	}

	@Test
	void findByUserAndListType_broadcastList_roundTrip() {
		List<String> display = List.of("Stop A", "Stop B", "Stop C");
		List<String> normalized = List.of("stop a", "stop b", "stop c");

		placeListRepository.save(new UserPlaceList(userA, PlaceListType.BROADCAST, display, normalized));
		entityManager.flush();
		entityManager.clear();

		Optional<UserPlaceList> found = placeListRepository
				.findByUser_IdAndListType(userA.getId(), PlaceListType.BROADCAST);

		assertThat(found).isPresent();
		assertThat(found.get().getDisplayNames()).containsExactlyElementsOf(display);
		assertThat(found.get().getNormalizedNames()).containsExactlyElementsOf(normalized);
		assertThat(found.get().getListType()).isEqualTo(PlaceListType.BROADCAST);
	}

	@Test
	void findByUserAndListType_noWatchListReturnsEmpty() {
		// userA has no watch list yet
		assertThat(placeListRepository
				.findByUser_IdAndListType(userA.getId(), PlaceListType.WATCH))
				.isEmpty();
	}

	@Test
	void findByUserAndListType_watchAndBroadcastAreIndependent() {
		placeListRepository.save(new UserPlaceList(userA, PlaceListType.WATCH,
				List.of("Circle"), List.of("circle")));
		placeListRepository.save(new UserPlaceList(userA, PlaceListType.BROADCAST,
				List.of("Stop A", "Stop B"), List.of("stop a", "stop b")));
		entityManager.flush();
		entityManager.clear();

		Optional<UserPlaceList> watch = placeListRepository
				.findByUser_IdAndListType(userA.getId(), PlaceListType.WATCH);
		Optional<UserPlaceList> broadcast = placeListRepository
				.findByUser_IdAndListType(userA.getId(), PlaceListType.BROADCAST);

		assertThat(watch).isPresent();
		assertThat(watch.get().getDisplayNames()).containsExactly("Circle");

		assertThat(broadcast).isPresent();
		assertThat(broadcast.get().getDisplayNames()).containsExactly("Stop A", "Stop B");
	}

	@Test
	void findByUserAndListType_differentUsersDoNotInterfere() {
		placeListRepository.save(new UserPlaceList(userA, PlaceListType.WATCH,
				List.of("Kaneshie"), List.of("kaneshie")));
		placeListRepository.save(new UserPlaceList(userB, PlaceListType.WATCH,
				List.of("Tema"), List.of("tema")));
		entityManager.flush();
		entityManager.clear();

		assertThat(placeListRepository
				.findByUser_IdAndListType(userA.getId(), PlaceListType.WATCH).get()
				.getDisplayNames()).containsExactly("Kaneshie");

		assertThat(placeListRepository
				.findByUser_IdAndListType(userB.getId(), PlaceListType.WATCH).get()
				.getDisplayNames()).containsExactly("Tema");
	}

	// ── findAllByListType ─────────────────────────────────────────────────

	@Test
	void findAllByListType_returnsOnlyWatchLists() {
		placeListRepository.save(new UserPlaceList(userA, PlaceListType.WATCH,
				List.of("Circle"), List.of("circle")));
		placeListRepository.save(new UserPlaceList(userB, PlaceListType.WATCH,
				List.of("Tema"), List.of("tema")));
		placeListRepository.save(new UserPlaceList(userA, PlaceListType.BROADCAST,
				List.of("Stop A"), List.of("stop a")));
		entityManager.flush();
		entityManager.clear();

		List<UserPlaceList> watchLists = placeListRepository.findAllByListType(PlaceListType.WATCH);

		assertThat(watchLists).hasSize(2);
		assertThat(watchLists).allMatch(l -> l.getListType() == PlaceListType.WATCH);
	}

	@Test
	void findAllByListType_returnsOnlyBroadcastLists() {
		placeListRepository.save(new UserPlaceList(userA, PlaceListType.BROADCAST,
				List.of("Stop A"), List.of("stop a")));
		placeListRepository.save(new UserPlaceList(userA, PlaceListType.WATCH,
				List.of("Circle"), List.of("circle")));
		entityManager.flush();
		entityManager.clear();

		List<UserPlaceList> broadcastLists = placeListRepository.findAllByListType(PlaceListType.BROADCAST);

		assertThat(broadcastLists).hasSize(1);
		assertThat(broadcastLists.get(0).getNormalizedNames()).containsExactly("stop a");
	}

	@Test
	void findAllByListType_emptyWhenNoneExist() {
		assertThat(placeListRepository.findAllByListType(PlaceListType.BROADCAST)).isEmpty();
	}

	// ── display/normalized names JSON converter round-trip ────────────────

	@Test
	void stringListConverter_emptyListRoundTrip() {
		placeListRepository.save(new UserPlaceList(userA, PlaceListType.WATCH,
				List.of(), List.of()));
		entityManager.flush();
		entityManager.clear();

		UserPlaceList found = placeListRepository
				.findByUser_IdAndListType(userA.getId(), PlaceListType.WATCH).get();

		assertThat(found.getDisplayNames()).isEmpty();
		assertThat(found.getNormalizedNames()).isEmpty();
	}
}
