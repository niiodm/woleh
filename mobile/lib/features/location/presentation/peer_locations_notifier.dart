import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth_state.dart';
import '../../../core/ws_client.dart';
import '../../../core/ws_message.dart';
import '../../me/data/me_dto.dart';
import '../../me/presentation/me_notifier.dart';
import '../data/peer_location.dart';

part 'peer_locations_notifier.g.dart';

/// Last-known [PeerLocation] per peer user id from WebSocket `peer_location`.
///
/// - Updates on [PeerLocationMessage]; removes a key on [PeerLocationRevokedMessage].
/// - Incoming peer fixes are shown whenever received; **local** [MeProfile.locationSharingEnabled]
///   only controls publishing (`POST /me/location`), not whether you can see matched peers.
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
      state = {...state, msg.userId: PeerLocation.fromMessage(msg)};
      return;
    }
    if (msg is PeerLocationRevokedMessage) {
      if (!state.containsKey(msg.userId)) return;
      final next = Map<String, PeerLocation>.from(state)..remove(msg.userId);
      state = next;
    }
  }
}
