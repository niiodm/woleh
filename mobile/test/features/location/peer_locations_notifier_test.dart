import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:odm_clarity_woleh_mobile/core/auth_state.dart';
import 'package:odm_clarity_woleh_mobile/core/ws_client.dart';
import 'package:odm_clarity_woleh_mobile/core/ws_message.dart';
import 'package:odm_clarity_woleh_mobile/features/location/data/peer_location.dart';
import 'package:odm_clarity_woleh_mobile/features/location/presentation/peer_locations_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _StubWsClient extends WsClient {
  _StubWsClient(this._msgs);

  final Stream<WsMessage> _msgs;

  @override
  void build() {
    ref.onDispose(() {});
  }

  @override
  Stream<WsMessage> get messages => _msgs;
}

class _ControllableAuth extends AuthState {
  @override
  Future<String?> build() async => 'test-token';

  void signOutNow() => state = const AsyncData(null);
}

final _sharingTestProvider = StateProvider<bool>((ref) => true);

class _MeSharingToggle extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async {
    final sharing = ref.watch(_sharingTestProvider);
    return MeLoadSnapshot(
      me: MeResponse(
        profile: MeProfile(
          userId: '1',
          phoneE164: '+2331',
          locationSharingEnabled: sharing,
        ),
        permissions: const ['woleh.place.watch'],
        tier: 'free',
        limits: const MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
        subscription: const MeSubscription(status: 'none', inGracePeriod: false),
      ),
    );
  }
}

class _MeSharingOff extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
        me: MeResponse(
          profile: const MeProfile(
            userId: '1',
            phoneE164: '+2331',
            locationSharingEnabled: false,
          ),
          permissions: const ['woleh.place.watch'],
          tier: 'free',
          limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
          subscription: MeSubscription(status: 'none', inGracePeriod: false),
        ),
      );
}

PeerLocationMessage _peer({
  String userId = '42',
  double lat = 5.6037,
  double lng = -0.187,
}) =>
    PeerLocationMessage(userId: userId, latitude: lat, longitude: lng);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PeerLocationsNotifier', () {
    test('stores PeerLocationMessage by userId', () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        meNotifierProvider.overrideWith(_MeSharingToggle.new),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(peerLocationsNotifierProvider);
      await pumpEventQueue();

      sc.add(_peer());
      await pumpEventQueue();

      final Map<String, PeerLocation> map =
          container.read(peerLocationsNotifierProvider);
      expect(map, hasLength(1));
      expect(map['42']!.latitude, 5.6037);
    });

    test('latest PeerLocationMessage overwrites same userId', () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        meNotifierProvider.overrideWith(_MeSharingToggle.new),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(peerLocationsNotifierProvider);
      await pumpEventQueue();

      sc.add(_peer(lat: 1.0, lng: 2.0));
      sc.add(_peer(lat: 3.0, lng: 4.0));
      await pumpEventQueue();

      expect(container.read(peerLocationsNotifierProvider)['42']!.latitude, 3.0);
    });

    test('PeerLocationRevokedMessage removes entry', () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        meNotifierProvider.overrideWith(_MeSharingToggle.new),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(peerLocationsNotifierProvider);
      await pumpEventQueue();

      sc.add(_peer());
      sc.add(const PeerLocationRevokedMessage(userId: '42'));
      await pumpEventQueue();

      expect(container.read(peerLocationsNotifierProvider), isEmpty);
    });

    test('stores PeerLocationMessage when local sharing is off', () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        meNotifierProvider.overrideWith(_MeSharingOff.new),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(peerLocationsNotifierProvider);
      await pumpEventQueue();

      sc.add(_peer());
      await pumpEventQueue();

      final map = container.read(peerLocationsNotifierProvider);
      expect(map, hasLength(1));
      expect(map['42']!.latitude, 5.6037);
    });

    test('clears all when local sharing turns off', () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        meNotifierProvider.overrideWith(_MeSharingToggle.new),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(peerLocationsNotifierProvider);
      await pumpEventQueue();

      sc.add(_peer());
      await pumpEventQueue();
      expect(container.read(peerLocationsNotifierProvider), isNotEmpty);

      container.read(_sharingTestProvider.notifier).state = false;
      await pumpEventQueue();

      expect(container.read(peerLocationsNotifierProvider), isEmpty);
    });

    test('clears on sign-out', () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        meNotifierProvider.overrideWith(_MeSharingToggle.new),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(peerLocationsNotifierProvider);
      await pumpEventQueue();

      sc.add(_peer());
      await pumpEventQueue();
      expect(container.read(peerLocationsNotifierProvider), isNotEmpty);

      auth.signOutNow();
      await pumpEventQueue();

      expect(container.read(peerLocationsNotifierProvider), isEmpty);
    });

    test('UnknownMessage does not change map', () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        meNotifierProvider.overrideWith(_MeSharingToggle.new),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(peerLocationsNotifierProvider);
      await pumpEventQueue();

      sc.add(_peer());
      sc.add(const UnknownMessage('match'));
      await pumpEventQueue();

      expect(container.read(peerLocationsNotifierProvider), hasLength(1));
    });
  });
}
