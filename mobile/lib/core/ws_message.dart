// Sealed hierarchy of decoded WebSocket messages for /ws/v1/transit.
// Heartbeats are discarded by WsClient before reaching this layer.

sealed class WsMessage {
  const WsMessage();
}

/// A real-time match event: the server found at least one name in common
/// between this user's list and another user's list.
final class MatchMessage extends WsMessage {
  const MatchMessage({
    required this.matchedNames,
    required this.counterpartyUserId,
    required this.kind,
  });

  /// Normalised names that are in both lists.
  final List<String> matchedNames;

  /// The other user's ID (opaque string; stringified Long on the server).
  final String counterpartyUserId;

  /// `"watcher"` when this user is the watcher, `"broadcaster"` when
  /// this user is the broadcaster.
  final String kind;
}

/// Match-scoped live location from a peer ([`API_CONTRACT.md`](../../../docs/API_CONTRACT.md) §8.2).
final class PeerLocationMessage extends WsMessage {
  const PeerLocationMessage({
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.heading,
    this.speed,
    this.receivedAt,
  });

  /// Publisher user id (stringified Long on the server).
  final String userId;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? heading;
  final double? speed;
  final DateTime? receivedAt;
}

/// Publisher turned off location sharing — drop their marker ([`API_CONTRACT.md`](../../../docs/API_CONTRACT.md) §8.3).
final class PeerLocationRevokedMessage extends WsMessage {
  const PeerLocationRevokedMessage({required this.userId});

  final String userId;
}

/// A message type the client does not recognise — surfaced for
/// forward-compatibility so callers can choose to ignore it gracefully.
final class UnknownMessage extends WsMessage {
  const UnknownMessage(this.type);

  final String type;
}
