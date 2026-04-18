package odm.clarity.woleh.location;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class LastKnownLocationStoreTest {

	private LastKnownLocationStore store;

	@BeforeEach
	void setUp() {
		store = new LastKnownLocationStore();
	}

	@Test
	void get_whenMissing_isEmpty() {
		assertThat(store.get(99L)).isEmpty();
	}

	@Test
	void put_thenGet_returnsCoordinates() {
		store.put(1L, 5.6037, -0.187);
		Optional<LatLon> p = store.get(1L);
		assertThat(p).isPresent();
		assertThat(p.get().latitude()).isEqualTo(5.6037);
		assertThat(p.get().longitude()).isEqualTo(-0.187);
	}

	@Test
	void put_overwritesPriorValue() {
		store.put(2L, 1.0, 2.0);
		store.put(2L, 3.0, 4.0);
		LatLon p = store.get(2L).orElseThrow();
		assertThat(p.latitude()).isEqualTo(3.0);
		assertThat(p.longitude()).isEqualTo(4.0);
	}

	@Test
	void usersAreIndependent() {
		store.put(10L, 1.0, 1.0);
		store.put(11L, 2.0, 2.0);
		assertThat(store.get(10L).orElseThrow().latitude()).isEqualTo(1.0);
		assertThat(store.get(11L).orElseThrow().latitude()).isEqualTo(2.0);
	}
}
