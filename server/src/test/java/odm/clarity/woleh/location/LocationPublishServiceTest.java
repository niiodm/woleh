package odm.clarity.woleh.location;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Optional;
import java.util.Set;

import odm.clarity.woleh.api.dto.PublishLocationRequest;
import odm.clarity.woleh.common.error.LocationSharingDisabledException;
import odm.clarity.woleh.common.error.PermissionDeniedException;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.places.MatchAdjacencyRegistry;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.subscription.EntitlementService;
import odm.clarity.woleh.subscription.Entitlements;
import odm.clarity.woleh.ws.PeerLocationEvent;
import odm.clarity.woleh.ws.WsSessionRegistry;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

class LocationPublishServiceTest {

	private UserRepository userRepository;
	private EntitlementService entitlementService;
	private MatchAdjacencyRegistry matchAdjacencyRegistry;
	private WsSessionRegistry wsSessionRegistry;
	private LocationPublishService service;

	private static final Entitlements WATCH_ENT = new Entitlements(
			List.of("woleh.place.watch"), "free", 5, 0, "none", null, false);

	@BeforeEach
	void setUp() {
		userRepository = Mockito.mock(UserRepository.class);
		entitlementService = Mockito.mock(EntitlementService.class);
		matchAdjacencyRegistry = Mockito.mock(MatchAdjacencyRegistry.class);
		wsSessionRegistry = Mockito.mock(WsSessionRegistry.class);
		service = new LocationPublishService(
				userRepository, entitlementService, matchAdjacencyRegistry, wsSessionRegistry);
	}

	@Test
	void publish_sharingDisabled_throwsAndDoesNotTouchAdjacencyOrWs() {
		User u = new User("+2331");
		u.setLocationSharingEnabled(false);
		when(userRepository.findById(1L)).thenReturn(Optional.of(u));
		when(entitlementService.computeEntitlements(1L)).thenReturn(WATCH_ENT);

		assertThatThrownBy(() -> service.publish(1L, sampleRequest()))
				.isInstanceOf(LocationSharingDisabledException.class);
		verify(matchAdjacencyRegistry, never()).getCounterparties(any());
		verify(wsSessionRegistry, never()).sendPeerLocationEvent(any(), any());
	}

	@Test
	void publish_noCounterparties_doesNotSendWs() {
		User u = sharingUser();
		when(userRepository.findById(1L)).thenReturn(Optional.of(u));
		when(entitlementService.computeEntitlements(1L)).thenReturn(WATCH_ENT);
		when(matchAdjacencyRegistry.getCounterparties(1L)).thenReturn(Set.of());

		service.publish(1L, sampleRequest());

		verify(wsSessionRegistry, never()).sendPeerLocationEvent(any(), any());
	}

	@Test
	void publish_forwardsToEachCounterpartyOnly() {
		User u = sharingUser();
		when(userRepository.findById(1L)).thenReturn(Optional.of(u));
		when(entitlementService.computeEntitlements(1L)).thenReturn(WATCH_ENT);
		when(matchAdjacencyRegistry.getCounterparties(1L)).thenReturn(Set.of(10L, 11L));

		service.publish(1L, new PublishLocationRequest(5.6, -0.18, 12.0, 90.0, 1.5, null));

		ArgumentCaptor<PeerLocationEvent> cap = ArgumentCaptor.forClass(PeerLocationEvent.class);
		verify(wsSessionRegistry).sendPeerLocationEvent(eq(10L), cap.capture());
		PeerLocationEvent e10 = cap.getValue();
		assertThat(e10.userId()).isEqualTo("1");
		assertThat(e10.latitude()).isEqualTo(5.6);
		assertThat(e10.longitude()).isEqualTo(-0.18);
		assertThat(e10.accuracyMeters()).isEqualTo(12.0);
		assertThat(e10.heading()).isEqualTo(90.0);
		assertThat(e10.speed()).isEqualTo(1.5);
		assertThat(e10.receivedAt()).isNotNull();

		verify(wsSessionRegistry).sendPeerLocationEvent(eq(11L), any(PeerLocationEvent.class));
	}

	@Test
	void publish_withoutMatchingPermissions_throws() {
		User u = sharingUser();
		when(userRepository.findById(1L)).thenReturn(Optional.of(u));
		when(entitlementService.computeEntitlements(1L)).thenReturn(
				new Entitlements(List.of("woleh.account.profile"), "free", 5, 0, "none", null, false));

		assertThatThrownBy(() -> service.publish(1L, sampleRequest()))
				.isInstanceOf(PermissionDeniedException.class);
		verify(wsSessionRegistry, never()).sendPeerLocationEvent(any(), any());
	}

	@Test
	void setLocationSharingEnabled_whenTurningOff_notifiesPeers() {
		User u = sharingUser();
		when(userRepository.findById(7L)).thenReturn(Optional.of(u));
		when(entitlementService.computeEntitlements(7L)).thenReturn(WATCH_ENT);
		when(matchAdjacencyRegistry.getCounterparties(7L)).thenReturn(Set.of(20L, 21L));

		boolean result = service.setLocationSharingEnabled(7L, false);

		assertThat(result).isFalse();
		assertThat(u.isLocationSharingEnabled()).isFalse();
		verify(userRepository).save(u);
		verify(wsSessionRegistry).sendPeerLocationRevoked(20L, "7");
		verify(wsSessionRegistry).sendPeerLocationRevoked(21L, "7");
	}

	@Test
	void setLocationSharingEnabled_whenAlreadyOff_doesNotNotify() {
		User u = new User("+2332");
		u.setLocationSharingEnabled(false);
		when(userRepository.findById(7L)).thenReturn(Optional.of(u));
		when(entitlementService.computeEntitlements(7L)).thenReturn(WATCH_ENT);

		service.setLocationSharingEnabled(7L, false);

		verify(wsSessionRegistry, never()).sendPeerLocationRevoked(any(), any());
	}

	@Test
	void setLocationSharingEnabled_whenEnabling_doesNotNotifyRevoke() {
		User u = new User("+2333");
		u.setLocationSharingEnabled(false);
		when(userRepository.findById(7L)).thenReturn(Optional.of(u));
		when(entitlementService.computeEntitlements(7L)).thenReturn(WATCH_ENT);

		boolean result = service.setLocationSharingEnabled(7L, true);

		assertThat(result).isTrue();
		verify(wsSessionRegistry, never()).sendPeerLocationRevoked(any(), any());
	}

	private static User sharingUser() {
		User u = new User("+2330");
		u.setLocationSharingEnabled(true);
		return u;
	}

	private static PublishLocationRequest sampleRequest() {
		return new PublishLocationRequest(5.6037, -0.187, null, null, null, null);
	}
}
