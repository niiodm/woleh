import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:odm_clarity_woleh_mobile/core/auth_state.dart';
import 'package:odm_clarity_woleh_mobile/core/ws_client.dart';
import 'package:odm_clarity_woleh_mobile/core/ws_message.dart';

// ---------------------------------------------------------------------------
// Fake WebSocket channel
// ---------------------------------------------------------------------------

class _FakeChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final _sc = StreamController<dynamic>();

  // Test helpers — simulate the server pushing data to the client.
  void serverSend(String msg) => _sc.add(msg);
  void serverClose() => _sc.close();
  void serverError(Object err) => _sc.addError(err);

  @override
  Stream<dynamic> get stream => _sc.stream;

  @override
  WebSocketSink get sink => _FakeSink(_sc);

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._sc);

  final StreamController<dynamic> _sc;

  @override
  void add(Object? data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_sc.isClosed) await _sc.close();
  }

  @override
  Future<void> get done => _sc.done;
}

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

/// Auth stub that resolves immediately with a token.
class _AuthWithToken extends AuthState {
  @override
  Future<String?> build() async => 'test-jwt';
}

/// Auth stub that resolves immediately with no token (signed-out).
class _AuthSignedOut extends AuthState {
  @override
  Future<String?> build() async => null;
}

// ---------------------------------------------------------------------------
// Test WsClient subclass
// ---------------------------------------------------------------------------

class _TestWsClient extends WsClient {
  _TestWsClient(this._factory);

  final WebSocketChannel Function(Uri) _factory;

  @override
  WebSocketChannel createChannel(Uri uri) => _factory(uri);
}

// ---------------------------------------------------------------------------
// Helper: build a ProviderContainer with test overrides
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({
  required AuthState Function() authFactory,
  required WebSocketChannel Function(Uri) channelFactory,
}) {
  return ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(authFactory),
      wsClientProvider
          .overrideWith(() => _TestWsClient(channelFactory)),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Backoff delay table ────────────────────────────────────────────────────

  group('reconnectDelay', () {
    test('follows min(2s × 2^attempt, 60s) schedule', () {
      expect(WsClient.reconnectDelay(0), const Duration(seconds: 2));
      expect(WsClient.reconnectDelay(1), const Duration(seconds: 4));
      expect(WsClient.reconnectDelay(2), const Duration(seconds: 8));
      expect(WsClient.reconnectDelay(3), const Duration(seconds: 16));
      expect(WsClient.reconnectDelay(4), const Duration(seconds: 32));
      // 2^5 = 32 × 2s = 64s → capped at 60s
      expect(WsClient.reconnectDelay(5), const Duration(seconds: 60));
      // Higher attempts are still capped.
      expect(WsClient.reconnectDelay(10), const Duration(seconds: 60));
    });
  });

  // ── Reconnect timing via fakeAsync ─────────────────────────────────────────

  group('reconnect backoff schedule', () {
    test('reconnects after 2 s, then 4 s on repeated disconnects', () {
      fakeAsync((fake) {
        int channelCount = 0;
        _FakeChannel? lastChannel;

        final container = _makeContainer(
          authFactory: _AuthWithToken.new,
          channelFactory: (uri) {
            channelCount++;
            return lastChannel = _FakeChannel();
          },
        );
        addTearDown(container.dispose);

        // Initialize the provider; auth listener fires after microtasks.
        container.read(wsClientProvider);
        fake.flushMicrotasks(); // Resolve auth future → connect() called.
        expect(channelCount, 1);

        // Simulate server-initiated close → _onDone → _scheduleReconnect(2s)
        lastChannel!.serverClose();
        fake.flushMicrotasks();

        // 1.9 s — no reconnect yet.
        fake.elapse(const Duration(milliseconds: 1900));
        expect(channelCount, 1);

        // 2.0 s total — timer fires, second connect.
        fake.elapse(const Duration(milliseconds: 100));
        expect(channelCount, 2);

        // Second close → _scheduleReconnect(4s) (attempt=1).
        lastChannel!.serverClose();
        fake.flushMicrotasks();

        fake.elapse(const Duration(seconds: 3));
        expect(channelCount, 2); // Not yet.

        fake.elapse(const Duration(seconds: 1));
        expect(channelCount, 3); // Third connect after 4 s.
      });
    });
  });

  // ── Heartbeat filtering ────────────────────────────────────────────────────

  group('heartbeat handling', () {
    test('heartbeat message is not forwarded to messages stream', () async {
      final messages = <WsMessage>[];
      _FakeChannel? ch;

      final container = _makeContainer(
        authFactory: _AuthWithToken.new,
        channelFactory: (_) => ch = _FakeChannel(),
      );
      addTearDown(container.dispose);

      container.read(wsClientProvider.notifier).messages.listen(messages.add);
      container.read(wsClientProvider);
      // Drain microtasks: resolve auth future → listener fires → connect().
      await pumpEventQueue();

      ch!.serverSend(jsonEncode({'type': 'heartbeat', 'data': 'ping'}));
      // Drain again: deliver event through the stream chain.
      await pumpEventQueue();

      expect(messages, isEmpty);
    });
  });

  // ── Unknown message type ───────────────────────────────────────────────────

  group('unknown message type', () {
    test('emits UnknownMessage for forward-compat; does not crash', () async {
      final messages = <WsMessage>[];
      _FakeChannel? ch;

      final container = _makeContainer(
        authFactory: _AuthWithToken.new,
        channelFactory: (_) => ch = _FakeChannel(),
      );
      addTearDown(container.dispose);

      container.read(wsClientProvider.notifier).messages.listen(messages.add);
      container.read(wsClientProvider);
      await pumpEventQueue();

      ch!.serverSend(jsonEncode({'type': 'future_feature', 'data': {}}));
      await pumpEventQueue();

      expect(messages, hasLength(1));
      expect(messages[0], isA<UnknownMessage>());
      expect((messages[0] as UnknownMessage).type, 'future_feature');
    });
  });

  // ── MatchMessage parsing ───────────────────────────────────────────────────

  group('MatchMessage parsing', () {
    test('parses match envelope into MatchMessage with correct fields',
        () async {
      final messages = <WsMessage>[];
      _FakeChannel? ch;

      final container = _makeContainer(
        authFactory: _AuthWithToken.new,
        channelFactory: (_) => ch = _FakeChannel(),
      );
      addTearDown(container.dispose);

      container.read(wsClientProvider.notifier).messages.listen(messages.add);
      container.read(wsClientProvider);
      await pumpEventQueue();

      ch!.serverSend(jsonEncode({
        'type': 'match',
        'data': {
          'matchedNames': ['madina', 'lapaz'],
          'counterpartyUserId': '42',
          'kind': 'watcher',
        },
      }));
      await pumpEventQueue();

      expect(messages, hasLength(1));
      final msg = messages[0] as MatchMessage;
      expect(msg.matchedNames, ['madina', 'lapaz']);
      expect(msg.counterpartyUserId, '42');
      expect(msg.kind, 'watcher');
    });

    test('receiving a match message resets the backoff attempt counter', () {
      fakeAsync((fake) {
        int channelCount = 0;
        _FakeChannel? lastChannel;

        final container = _makeContainer(
          authFactory: _AuthWithToken.new,
          channelFactory: (uri) {
            channelCount++;
            return lastChannel = _FakeChannel();
          },
        );
        addTearDown(container.dispose);

        container.read(wsClientProvider);
        fake.flushMicrotasks();
        expect(channelCount, 1);

        // First disconnect → attempt=0 → 2 s delay.
        lastChannel!.serverClose();
        fake.flushMicrotasks();
        fake.elapse(const Duration(seconds: 2));
        expect(channelCount, 2);

        // Receive a message → resets _attempt to 0.
        lastChannel!.serverSend(jsonEncode({
          'type': 'match',
          'data': {
            'matchedNames': ['madina'],
            'counterpartyUserId': '7',
            'kind': 'broadcaster',
          },
        }));
        fake.flushMicrotasks();

        // Second disconnect → attempt still 0 (reset by receipt) → 2 s delay.
        lastChannel!.serverClose();
        fake.flushMicrotasks();
        fake.elapse(const Duration(seconds: 2));
        expect(channelCount, 3);
      });
    });
  });
}
