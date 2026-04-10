package odm.clarity.woleh.places;

import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;

import odm.clarity.woleh.model.PlaceListType;
import odm.clarity.woleh.model.UserPlaceList;
import odm.clarity.woleh.push.FcmService;
import odm.clarity.woleh.repository.UserPlaceListRepository;
import odm.clarity.woleh.ws.WsSessionRegistry;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class MatchingServiceTest {

	private UserPlaceListRepository placeListRepository;
	private WsSessionRegistry wsSessionRegistry;
	private FcmService fcmService;
	private MatchingService matchingService;

	@BeforeEach
	void setUp() {
		placeListRepository = mock(UserPlaceListRepository.class);
		wsSessionRegistry = mock(WsSessionRegistry.class);
		fcmService = mock(FcmService.class);
		when(wsSessionRegistry.hasOpenSession(anyLong())).thenReturn(true);
		matchingService = new MatchingService(placeListRepository, wsSessionRegistry, fcmService, new SimpleMeterRegistry());
	}

	// ── dispatchBroadcastMatches ──────────────────────────────────────────

	@Test
	void dispatchBroadcastMatches_emptyBroadcastList_noQueryNoEvents() {
		matchingService.dispatchBroadcastMatches(1L, List.of());

		verify(placeListRepository, never()).findAllByListType(any());
		verify(wsSessionRegistry, never()).sendMatchEvent(any(), any(), any(), any());
	}

	@Test
	void dispatchBroadcastMatches_noWatchLists_noEvents() {
		when(placeListRepository.findAllByListType(PlaceListType.WATCH))
				.thenReturn(List.of());

		matchingService.dispatchBroadcastMatches(1L, List.of("circle", "tema"));

		verify(wsSessionRegistry, never()).sendMatchEvent(any(), any(), any(), any());
	}

	@Test
	void dispatchBroadcastMatches_disjointWatchList_noEvents() {
		UserPlaceList watchList = mockWatchList(10L, List.of("accra central", "kaneshie"));
		when(placeListRepository.findAllByListType(PlaceListType.WATCH))
				.thenReturn(List.of(watchList));

		matchingService.dispatchBroadcastMatches(1L, List.of("circle", "tema"));

		verify(wsSessionRegistry, never()).sendMatchEvent(any(), any(), any(), any());
		verify(fcmService, never()).sendNotification(anyLong(), any(), any(), any());
	}

	@Test
	void dispatchBroadcastMatches_whenNoOpenSession_sendsFcmToOfflineUser() {
		when(wsSessionRegistry.hasOpenSession(anyLong())).thenReturn(false);
		UserPlaceList watchList = mockWatchList(10L, List.of("circle", "kaneshie"));
		when(placeListRepository.findAllByListType(PlaceListType.WATCH))
				.thenReturn(List.of(watchList));

		matchingService.dispatchBroadcastMatches(1L, List.of("circle", "tema"));

		verify(wsSessionRegistry, times(2)).sendMatchEvent(any(), any(), any(), any());
		verify(fcmService).sendNotification(
				eq(10L),
				eq("Match found"),
				eq("A vehicle covers your stops: circle"),
				eq(Map.of("kind", "match", "counterpartyUserId", "1")));
		verify(fcmService).sendNotification(
				eq(1L),
				eq("Match found"),
				eq("A vehicle covers your stops: circle"),
				eq(Map.of("kind", "match", "counterpartyUserId", "10")));
	}

	@Test
	void dispatchBroadcastMatches_singleMatch_notifiesBothParties() {
		UserPlaceList watchList = mockWatchList(10L, List.of("circle", "kaneshie"));
		when(placeListRepository.findAllByListType(PlaceListType.WATCH))
				.thenReturn(List.of(watchList));

		matchingService.dispatchBroadcastMatches(1L, List.of("circle", "tema"));

		// Watcher notified (broadcaster = 1L is the counterparty)
		verify(wsSessionRegistry).sendMatchEvent(
				eq(10L), eq(List.of("circle")), eq(1L), eq("broadcast_to_watch"));
		// Broadcaster notified (watcher = 10L is the counterparty)
		verify(wsSessionRegistry).sendMatchEvent(
				eq(1L), eq(List.of("circle")), eq(10L), eq("broadcast_to_watch"));
	}

	@Test
	void dispatchBroadcastMatches_multipleMatchedNames_allIncluded() {
		UserPlaceList watchList = mockWatchList(10L, List.of("circle", "tema", "kaneshie"));
		when(placeListRepository.findAllByListType(PlaceListType.WATCH))
				.thenReturn(List.of(watchList));

		// Broadcast covers circle + tema; kaneshie is not broadcast
		matchingService.dispatchBroadcastMatches(1L, List.of("circle", "tema", "accra central"));

		verify(wsSessionRegistry).sendMatchEvent(
				eq(10L), eq(List.of("circle", "tema")), eq(1L), eq("broadcast_to_watch"));
		verify(wsSessionRegistry).sendMatchEvent(
				eq(1L), eq(List.of("circle", "tema")), eq(10L), eq("broadcast_to_watch"));
	}

	@Test
	void dispatchBroadcastMatches_twoWatchers_onlyOverlappingNotified() {
		UserPlaceList watcherA = mockWatchList(10L, List.of("circle", "kaneshie"));
		UserPlaceList watcherB = mockWatchList(20L, List.of("accra central")); // no overlap
		when(placeListRepository.findAllByListType(PlaceListType.WATCH))
				.thenReturn(List.of(watcherA, watcherB));

		matchingService.dispatchBroadcastMatches(1L, List.of("circle", "tema"));

		// watcher A (overlaps on "circle") → 2 events
		verify(wsSessionRegistry).sendMatchEvent(eq(10L), anyList(), eq(1L), any());
		verify(wsSessionRegistry).sendMatchEvent(eq(1L), anyList(), eq(10L), any());
		// watcher B (no overlap) → no events
		verify(wsSessionRegistry, never()).sendMatchEvent(eq(20L), anyList(), any(), any());
		verify(wsSessionRegistry, never()).sendMatchEvent(any(), anyList(), eq(20L), any());
	}

	@Test
	void dispatchBroadcastMatches_twoMatchingWatchers_fourTotalEvents() {
		UserPlaceList watcherA = mockWatchList(10L, List.of("circle"));
		UserPlaceList watcherB = mockWatchList(20L, List.of("circle"));
		when(placeListRepository.findAllByListType(PlaceListType.WATCH))
				.thenReturn(List.of(watcherA, watcherB));

		matchingService.dispatchBroadcastMatches(1L, List.of("circle"));

		// 2 events per matched watcher × 2 watchers = 4
		verify(wsSessionRegistry, times(4)).sendMatchEvent(any(), any(), any(), any());
	}

	// ── dispatchWatchMatches ──────────────────────────────────────────────

	@Test
	void dispatchWatchMatches_emptyWatchList_noQueryNoEvents() {
		matchingService.dispatchWatchMatches(10L, List.of());

		verify(placeListRepository, never()).findAllByListType(any());
		verify(wsSessionRegistry, never()).sendMatchEvent(any(), any(), any(), any());
	}

	@Test
	void dispatchWatchMatches_noBroadcastLists_noEvents() {
		when(placeListRepository.findAllByListType(PlaceListType.BROADCAST))
				.thenReturn(List.of());

		matchingService.dispatchWatchMatches(10L, List.of("circle"));

		verify(wsSessionRegistry, never()).sendMatchEvent(any(), any(), any(), any());
	}

	@Test
	void dispatchWatchMatches_matchingBroadcast_notifiesBothParties() {
		UserPlaceList broadcastList = mockBroadcastList(1L, List.of("circle", "tema", "kaneshie"));
		when(placeListRepository.findAllByListType(PlaceListType.BROADCAST))
				.thenReturn(List.of(broadcastList));

		matchingService.dispatchWatchMatches(10L, List.of("circle", "accra central"));

		// Watcher notified (broadcaster = 1L is counterparty)
		verify(wsSessionRegistry).sendMatchEvent(
				eq(10L), eq(List.of("circle")), eq(1L), eq("broadcast_to_watch"));
		// Broadcaster notified (watcher = 10L is counterparty)
		verify(wsSessionRegistry).sendMatchEvent(
				eq(1L), eq(List.of("circle")), eq(10L), eq("broadcast_to_watch"));
	}

	@Test
	void dispatchWatchMatches_disjointBroadcast_noEvents() {
		UserPlaceList broadcastList = mockBroadcastList(1L, List.of("kaneshie", "tema"));
		when(placeListRepository.findAllByListType(PlaceListType.BROADCAST))
				.thenReturn(List.of(broadcastList));

		matchingService.dispatchWatchMatches(10L, List.of("circle", "accra central"));

		verify(wsSessionRegistry, never()).sendMatchEvent(any(), any(), any(), any());
	}

	// ── helpers ───────────────────────────────────────────────────────────

	private static UserPlaceList mockWatchList(Long userId, List<String> normalizedNames) {
		return mockList(userId, PlaceListType.WATCH, normalizedNames);
	}

	private static UserPlaceList mockBroadcastList(Long userId, List<String> normalizedNames) {
		return mockList(userId, PlaceListType.BROADCAST, normalizedNames);
	}

	private static UserPlaceList mockList(Long userId, PlaceListType type,
			List<String> normalizedNames) {
		UserPlaceList list = mock(UserPlaceList.class);
		when(list.getUserId()).thenReturn(userId);
		when(list.getListType()).thenReturn(type);
		when(list.getNormalizedNames()).thenReturn(normalizedNames);
		return list;
	}
}
