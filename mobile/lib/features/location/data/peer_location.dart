import 'package:flutter/foundation.dart';

import '../../../core/ws_message.dart';

/// Last known coordinates for a matched peer (Phase 4 live map).
@immutable
class PeerLocation {
  const PeerLocation({
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.heading,
    this.speed,
    this.receivedAt,
  });

  final String userId;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? heading;
  final double? speed;
  final DateTime? receivedAt;

  factory PeerLocation.fromMessage(PeerLocationMessage m) => PeerLocation(
        userId: m.userId,
        latitude: m.latitude,
        longitude: m.longitude,
        accuracyMeters: m.accuracyMeters,
        heading: m.heading,
        speed: m.speed,
        receivedAt: m.receivedAt,
      );
}
