import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth_state.dart';
import 'ws_message.dart';

part 'ws_client.g.dart';

/// Exposed UI state for the transit WebSocket (Phase 3.3 / NFR-2).
enum WsConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected,
}

// WS base URL is derived from the API base URL by substituting the scheme.
// Matches the --dart-define=API_BASE_URL=... convention used by api_client.dart.
const _kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

const _kBaseReconnectDelay = Duration(seconds: 2);
const _kMaxReconnectDelay = Duration(seconds: 60);

/// After this many reconnect scheduling cycles without a successful message,
/// [WsConnectionState] becomes [WsConnectionState.disconnected].
const _kMaxReconnectCycles = 10;

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages the lifecycle of the `/ws/v1/transit` WebSocket connection.
///
/// **Usage:** watch [wsClientProvider] once in the top-level widget (e.g.
/// `WolehApp`) to eagerly initialise it. Obtain decoded messages via
/// `ref.read(wsClientProvider.notifier).messages`.
///
/// **Auth integration:** the notifier listens to [authStateProvider] and
/// auto-connects when a token is present, auto-disconnects on sign-out.
///
/// **Reconnect backoff:** closed connections are rescheduled after
/// `min(2s × 2^attempt, 60s)`. The attempt counter resets on every
/// successfully received message.
@Riverpod(keepAlive: true)
class WsClient extends _$WsClient {
  WebSocketChannel? _channel;
  StreamController<WsMessage>? _msgController;
  Timer? _reconnectTimer;
  int _attempt = 0;
  String? _currentToken;
  late final ValueNotifier<WsConnectionState> _connectionState;

  /// Current WS connectivity for UI (banner, etc.).
  ValueNotifier<WsConnectionState> get connectionState => _connectionState;

  @override
  void build() {
    _connectionState =
        ValueNotifier<WsConnectionState>(WsConnectionState.disconnected);
    _msgController = StreamController<WsMessage>.broadcast();

    ref.listen<AsyncValue<String?>>(
      authStateProvider,
      (previous, next) {
        final token = next.valueOrNull;
        if (token != null) {
          if (token != _currentToken) {
            _currentToken = token;
            _attempt = 0;
            connect();
          }
        } else {
          _currentToken = null;
          disconnect();
        }
      },
      fireImmediately: true,
    );

    ref.onDispose(() {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      // Clear token first so _scheduleReconnect no-ops if sink.close()
      // triggers onDone synchronously (e.g. inside fakeAsync in widget tests).
      _currentToken = null;
      _channel?.sink.close();
      _channel = null;
      _msgController?.close();
      _msgController = null;
      _connectionState.dispose();
    });
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Decoded, deduplicated messages from the server (heartbeats excluded).
  Stream<WsMessage> get messages => _msgController!.stream;

  /// Opens a new WebSocket connection using the current auth token.
  ///
  /// Cancels any pending reconnect timer and closes an existing channel
  /// before opening the new one. No-ops if no token is available.
  void connect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;

    final token = _currentToken ?? ref.read(authStateProvider).valueOrNull;
    if (token == null) return;

    _setConnectionState(WsConnectionState.connecting);

    final wsBase = _kApiBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final uri = Uri.parse('$wsBase/ws/v1/transit?access_token=$token');

    _channel = createChannel(uri);
    _channel!.stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  /// Closes the active connection and cancels any pending reconnect.
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
    _attempt = 0;
    _setConnectionState(WsConnectionState.disconnected);
  }

  /// Resets backoff and opens a new connection (e.g. user tapped **Retry**
  /// after [WsConnectionState.disconnected]).
  void retryConnection() {
    if (ref.read(authStateProvider).valueOrNull == null) return;
    _attempt = 0;
    connect();
  }

  // ── Overridable for testing ─────────────────────────────────────────────

  /// Creates a [WebSocketChannel] for [uri].
  ///
  /// Overridable so tests can inject a mock channel without making real
  /// network connections.
  @visibleForTesting
  WebSocketChannel createChannel(Uri uri) => WebSocketChannel.connect(uri);

  // ── Backoff helper (also testable in isolation) ─────────────────────────

  /// Computes the reconnect delay for the given [attempt] number.
  ///
  /// `delay = min(baseDelay × 2^attempt, maxDelay)`
  /// where base = 2 s and max = 60 s.
  static Duration reconnectDelay(int attempt) {
    final exp = attempt.clamp(0, 10);
    final raw = Duration(
        milliseconds: _kBaseReconnectDelay.inMilliseconds * (1 << exp));
    return raw < _kMaxReconnectDelay ? raw : _kMaxReconnectDelay;
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _onData(dynamic rawData) {
    // Reset backoff on any successfully received message (including heartbeat).
    _attempt = 0;
    _setConnectionState(WsConnectionState.connected);

    try {
      final envelope =
          jsonDecode(rawData as String) as Map<String, dynamic>;
      final type = envelope['type'] as String?;

      if (type == 'heartbeat') return; // Silently discard heartbeats.

      if (type == 'match') {
        final data = envelope['data'] as Map<String, dynamic>;
        _msgController?.add(MatchMessage(
          matchedNames:
              List<String>.from(data['matchedNames'] as List),
          counterpartyUserId: data['counterpartyUserId'] as String,
          kind: data['kind'] as String,
        ));
        return;
      }

      if (type == 'peer_location') {
        final data = envelope['data'] as Map<String, dynamic>;
        DateTime? receivedAt;
        final rawAt = data['receivedAt'];
        if (rawAt is String) {
          receivedAt = DateTime.tryParse(rawAt);
        }
        _msgController?.add(PeerLocationMessage(
          userId: data['userId'] as String,
          latitude: (data['latitude'] as num).toDouble(),
          longitude: (data['longitude'] as num).toDouble(),
          accuracyMeters: _optionalDouble(data['accuracyMeters']),
          heading: _optionalDouble(data['heading']),
          speed: _optionalDouble(data['speed']),
          receivedAt: receivedAt,
        ));
        return;
      }

      if (type == 'peer_location_revoked') {
        final data = envelope['data'] as Map<String, dynamic>;
        _msgController?.add(PeerLocationRevokedMessage(
          userId: data['userId'] as String,
        ));
        return;
      }

      // Unknown type: log and forward for forward-compatibility.
      debugPrint('[WsClient] Unknown message type: $type');
      if (type != null) _msgController?.add(UnknownMessage(type));
    } catch (e) {
      debugPrint('[WsClient] Failed to parse message: $e');
    }
  }

  void _onError(Object error) {
    debugPrint('[WsClient] Connection error: $error');
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[WsClient] Connection closed');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_currentToken == null) return; // Don't reconnect after sign-out.
    _channel = null; // Channel is already closed; clear reference.
    if (_attempt >= _kMaxReconnectCycles) {
      _setConnectionState(WsConnectionState.disconnected);
      return;
    }
    final delay = reconnectDelay(_attempt);
    _attempt++;
    _setConnectionState(WsConnectionState.reconnecting);
    _reconnectTimer = Timer(delay, connect);
  }

  void _setConnectionState(WsConnectionState state) {
    if (_connectionState.value != state) {
      _connectionState.value = state;
    }
  }

  static double? _optionalDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return null;
  }
}
