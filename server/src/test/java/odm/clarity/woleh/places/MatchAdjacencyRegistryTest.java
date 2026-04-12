package odm.clarity.woleh.places;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Optional;
import java.util.Set;

import odm.clarity.woleh.model.PlaceListType;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.model.UserPlaceList;
import odm.clarity.woleh.repository.UserPlaceListRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class MatchAdjacencyRegistryTest {

	private UserPlaceListRepository repository;
	private MatchAdjacencyRegistry registry;

	@BeforeEach
	void setUp() {
		repository = mock(UserPlaceListRepository.class);
		registry = new MatchAdjacencyRegistry(repository);
	}

	@Test
	void rebuild_broadcasterLinksToWatcherWhenNamesIntersect() {
		long broadcasterId = 1L;
		long watcherId = 2L;

		UserPlaceList broadRow = broadcastList(broadcasterId, List.of("circle", "tema"));
		when(repository.findByUser_IdAndListType(broadcasterId, PlaceListType.BROADCAST))
				.thenReturn(Optional.of(broadRow));
		when(repository.findByUser_IdAndListType(broadcasterId, PlaceListType.WATCH))
				.thenReturn(Optional.empty());

		UserPlaceList watchList = watchList(watcherId, List.of("circle", "kaneshie"));
		when(repository.findAllByListType(PlaceListType.WATCH)).thenReturn(List.of(watchList));
		when(repository.findAllByListType(PlaceListType.BROADCAST)).thenReturn(List.of());

		registry.rebuildAdjacencyForUser(broadcasterId);

		assertThat(registry.getCounterparties(broadcasterId)).containsExactly(watcherId);
		assertThat(registry.getCounterparties(watcherId)).containsExactly(broadcasterId);
	}

	@Test
	void rebuild_watcherLinksToBroadcasterWhenNamesIntersect() {
		long watcherId = 2L;
		long broadcasterId = 1L;

		UserPlaceList watchRow = watchList(watcherId, List.of("circle"));
		when(repository.findByUser_IdAndListType(watcherId, PlaceListType.WATCH))
				.thenReturn(Optional.of(watchRow));
		when(repository.findByUser_IdAndListType(watcherId, PlaceListType.BROADCAST))
				.thenReturn(Optional.empty());

		UserPlaceList broadcastList = broadcastList(broadcasterId, List.of("circle", "tema"));
		when(repository.findAllByListType(PlaceListType.BROADCAST)).thenReturn(List.of(broadcastList));
		when(repository.findAllByListType(PlaceListType.WATCH)).thenReturn(List.of());

		registry.rebuildAdjacencyForUser(watcherId);

		assertThat(registry.getCounterparties(watcherId)).containsExactly(broadcasterId);
		assertThat(registry.getCounterparties(broadcasterId)).containsExactly(watcherId);
	}

	@Test
	void rebuild_disjointLists_removesPreviousEdge() {
		long broadcasterId = 1L;
		long watcherId = 2L;

		// First: intersect on "circle"
		UserPlaceList broadFirst = broadcastList(broadcasterId, List.of("circle"));
		when(repository.findByUser_IdAndListType(broadcasterId, PlaceListType.BROADCAST))
				.thenReturn(Optional.of(broadFirst));
		when(repository.findByUser_IdAndListType(broadcasterId, PlaceListType.WATCH))
				.thenReturn(Optional.empty());
		UserPlaceList watchA = watchList(watcherId, List.of("circle"));
		when(repository.findAllByListType(PlaceListType.WATCH)).thenReturn(List.of(watchA));

		registry.rebuildAdjacencyForUser(broadcasterId);
		assertThat(registry.getCounterparties(broadcasterId)).containsExactly(watcherId);

		// Second: no intersection
		UserPlaceList broadSecond = broadcastList(broadcasterId, List.of("tema"));
		when(repository.findByUser_IdAndListType(broadcasterId, PlaceListType.BROADCAST))
				.thenReturn(Optional.of(broadSecond));
		UserPlaceList watchB = watchList(watcherId, List.of("circle"));
		when(repository.findAllByListType(PlaceListType.WATCH)).thenReturn(List.of(watchB));

		Set<Long> lost = registry.rebuildAdjacencyForUser(broadcasterId);

		assertThat(lost).containsExactly(watcherId);
		assertThat(registry.getCounterparties(broadcasterId)).isEmpty();
		assertThat(registry.getCounterparties(watcherId)).isEmpty();
	}

	@Test
	void rebuild_emptyBroadcast_clearsEdges() {
		long broadcasterId = 1L;
		UserPlaceList emptyBroad = broadcastList(broadcasterId, List.of());
		when(repository.findByUser_IdAndListType(broadcasterId, PlaceListType.BROADCAST))
				.thenReturn(Optional.of(emptyBroad));
		when(repository.findByUser_IdAndListType(broadcasterId, PlaceListType.WATCH))
				.thenReturn(Optional.empty());

		registry.rebuildAdjacencyForUser(broadcasterId);

		assertThat(registry.getCounterparties(broadcasterId)).isEmpty();
	}

	private static UserPlaceList broadcastList(long userId, List<String> normalized) {
		User user = mock(User.class);
		when(user.getId()).thenReturn(userId);
		UserPlaceList list = new UserPlaceList(user, PlaceListType.BROADCAST, List.of(), normalized);
		return list;
	}

	private static UserPlaceList watchList(long userId, List<String> normalized) {
		User user = mock(User.class);
		when(user.getId()).thenReturn(userId);
		UserPlaceList list = new UserPlaceList(user, PlaceListType.WATCH, List.of(), normalized);
		return list;
	}
}
