import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:odm_clarity_woleh_mobile/core/auth_state.dart';
import 'package:odm_clarity_woleh_mobile/core/ws_client.dart';
import 'package:odm_clarity_woleh_mobile/core/ws_message.dart';
import 'package:odm_clarity_woleh_mobile/features/places/presentation/match_notifier.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

/// WsClient stub — exposes a test-controlled message stream.
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

/// AuthState stub — starts with a token; `signOutNow()` clears it.
class _ControllableAuth extends AuthState {
  @override
  Future<String?> build() async => 'test-token';

  void signOutNow() => state = const AsyncData(null);
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

MatchMessage _match({
  String name = 'Madina',
  String userId = '42',
  String kind = 'watcher',
}) =>
    MatchMessage(
      matchedNames: [name],
      counterpartyUserId: userId,
      kind: kind,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MatchNotifier', () {
    test('accumulates MatchMessages from WsClient stream (newest first)',
        () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(matchNotifierProvider);
      await pumpEventQueue();

      sc.add(_match(name: 'Madina'));
      sc.add(_match(name: 'Lapaz'));
      await pumpEventQueue();

      final state = container.read(matchNotifierProvider);
      expect(state.length, 2);
      // Newest first.
      expect(state[0].matchedNames, ['Lapaz']);
      expect(state[1].matchedNames, ['Madina']);
    });

    test('caps accumulated list at 20 entries', () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(matchNotifierProvider);
      await pumpEventQueue();

      for (int i = 0; i < 25; i++) {
        sc.add(_match(name: 'Place$i', userId: '$i'));
      }
      await pumpEventQueue();

      final state = container.read(matchNotifierProvider);
      expect(state.length, 20);
      // Entry 0 is the most-recently added (Place24).
      expect(state[0].matchedNames, ['Place24']);
    });

    test('clears list on sign-out', () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(matchNotifierProvider);
      await pumpEventQueue();

      sc.add(_match(name: 'Madina'));
      await pumpEventQueue();
      expect(container.read(matchNotifierProvider).length, 1);

      // Simulate sign-out.
      auth.signOutNow();
      await pumpEventQueue();

      expect(container.read(matchNotifierProvider), isEmpty);
    });

    test('dismiss removes entry at given index', () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(matchNotifierProvider);
      await pumpEventQueue();

      sc.add(_match(name: 'Lapaz'));
      sc.add(_match(name: 'Madina'));
      await pumpEventQueue();
      expect(container.read(matchNotifierProvider).length, 2);

      // Dismiss the first entry (Madina — newest).
      container.read(matchNotifierProvider.notifier).dismiss(0);

      final state = container.read(matchNotifierProvider);
      expect(state.length, 1);
      expect(state[0].matchedNames, ['Lapaz']);
    });

    test('UnknownMessage does not add to the list', () async {
      final sc = StreamController<WsMessage>.broadcast();
      final auth = _ControllableAuth();

      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => auth),
        wsClientProvider.overrideWith(() => _StubWsClient(sc.stream)),
      ]);
      addTearDown(container.dispose);

      container.read(matchNotifierProvider);
      await pumpEventQueue();

      sc.add(const UnknownMessage('future_feature'));
      await pumpEventQueue();

      expect(container.read(matchNotifierProvider), isEmpty);
    });
  });
}
