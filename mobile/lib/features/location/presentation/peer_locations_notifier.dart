import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth_state.dart';
import '../../../core/ws_client.dart';
import '../../../core/ws_message.dart';
import '../../me/data/me_dto.dart';
import '../../me/presentation/me_notifier.dart';
import '../../places/active_place_session.dart';
import '../../places/presentation/broadcast_notifier.dart';
import '../../places/presentation/watch_notifier.dart';
import '../data/peer_location.dart';

part 'peer_locations_notifier.g.dart';

/// Last-known [PeerLocation] per peer user id from WebSocket `peer_location`.
///
/// - Updates on [PeerLocationMessage]; removes a key on [PeerLocationRevokedMessage].
/// - Peer pins are shown only while [hasActivePlaceSession] is true for the local watch/broadcast
///   state (same gate as foreground `POST /me/location` publishing), so reconnecting without an
///   active list session
///   does not resurrect stale markers.
/// - **Local** [MeProfile.locationSharingEnabled] still controls publishing only; you can receive
///   peer fixes while sharing is off if you have an active place session.
/// - Clears all pins when the signed-in user **turns off** sharing (true → false) or signs out
///   ([MAP_LIVE_LOCATION_PLAN.md](../../../../../docs/MAP_LIVE_LOCATION_PLAN.md) §4.2).
@Riverpod(keepAlive: true)
class PeerLocationsNotifier extends _$PeerLocationsNotifier {
  StreamSubscription<WsMessage>? _sub;

  @override
  Map<String, PeerLocation> build() {
    _sub?.cancel();
    _sub = ref.read(wsClientProvider.notifier).messages.listen(_onMessage);

    ref.listen<AsyncValue<MeLoadSnapshot?>>(
      meNotifierProvider,
      (prev, next) {
        final wasOn =
            prev?.valueOrNull?.me.profile.locationSharingEnabled ?? false;
        final nowOn =
            next.valueOrNull?.me.profile.locationSharingEnabled ?? false;
        if (wasOn && !nowOn) {
          state = const {};
        }
      },
    );

    ref.listen<WatchState>(
      watchNotifierProvider,
      (_, __) => scheduleMicrotask(_syncPeersToPlaceSession),
      fireImmediately: true,
    );
    ref.listen<BroadcastState>(
      broadcastNotifierProvider,
      (_, __) => scheduleMicrotask(_syncPeersToPlaceSession),
      fireImmediately: true,
    );

    ref.listen<AsyncValue<String?>>(
      authStateProvider,
      (_, next) {
        if (next.valueOrNull == null) state = const {};
      },
    );

    ref.onDispose(() => _sub?.cancel());

    return const {};
  }

  void _onMessage(WsMessage msg) {
    if (msg is PeerLocationMessage) {
      if (!_placeSessionActive()) return;
      state = {...state, msg.userId: PeerLocation.fromMessage(msg)};
      return;
    }
    if (msg is PeerLocationRevokedMessage) {
      if (!state.containsKey(msg.userId)) return;
      final next = Map<String, PeerLocation>.from(state)..remove(msg.userId);
      state = next;
    }
  }

  bool _placeSessionActive() => hasActivePlaceSession(
        ref.read(watchNotifierProvider),
        ref.read(broadcastNotifierProvider),
      );

  void _syncPeersToPlaceSession() {
    if (!_placeSessionActive() && state.isNotEmpty) {
      state = const {};
    }
  }
}
