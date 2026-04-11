// DTOs for GET /api/v1/me (see API_CONTRACT.md §6.3 and §4).

import 'package:flutter/foundation.dart';

class MeProfile {
  const MeProfile({
    required this.userId,
    required this.phoneE164,
    this.displayName,
    this.locationSharingEnabled = true,
  });

  final String userId;
  final String phoneE164;
  final String? displayName;

  /// When true, server accepts {@code POST /api/v1/me/location} (Phase 4).
  final bool locationSharingEnabled;

  /// Returns [displayName] when set, otherwise falls back to [phoneE164].
  String get displayNameOrPhone => displayName?.isNotEmpty == true ? displayName! : phoneE164;

  factory MeProfile.fromJson(Map<String, dynamic> json) => MeProfile(
        userId: json['userId'].toString(),
        phoneE164: json['phoneE164'] as String,
        displayName: json['displayName'] as String?,
        locationSharingEnabled: json['locationSharingEnabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'phoneE164': phoneE164,
        'displayName': displayName,
        'locationSharingEnabled': locationSharingEnabled,
      };
}

class MeLimits {
  const MeLimits({
    required this.placeWatchMax,
    required this.placeBroadcastMax,
  });

  final int placeWatchMax;
  final int placeBroadcastMax;

  factory MeLimits.fromJson(Map<String, dynamic> json) => MeLimits(
        placeWatchMax: json['placeWatchMax'] as int,
        placeBroadcastMax: json['placeBroadcastMax'] as int,
      );

  Map<String, dynamic> toJson() => {
        'placeWatchMax': placeWatchMax,
        'placeBroadcastMax': placeBroadcastMax,
      };
}

class MeSubscription {
  const MeSubscription({
    required this.status,
    this.currentPeriodEnd,
    required this.inGracePeriod,
  });

  final String status;
  final String? currentPeriodEnd;
  final bool inGracePeriod;

  factory MeSubscription.fromJson(Map<String, dynamic> json) => MeSubscription(
        status: json['status'] as String,
        currentPeriodEnd: json['currentPeriodEnd'] as String?,
        inGracePeriod: json['inGracePeriod'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'status': status,
        'currentPeriodEnd': currentPeriodEnd,
        'inGracePeriod': inGracePeriod,
      };
}

class MeResponse {
  const MeResponse({
    required this.profile,
    required this.permissions,
    required this.tier,
    required this.limits,
    required this.subscription,
  });

  final MeProfile profile;
  final List<String> permissions;
  final String tier;
  final MeLimits limits;
  final MeSubscription subscription;

  bool hasPermission(String permission) => permissions.contains(permission);

  factory MeResponse.fromJson(Map<String, dynamic> json) => MeResponse(
        profile: MeProfile.fromJson(json['profile'] as Map<String, dynamic>),
        permissions: List<String>.from(json['permissions'] as List),
        tier: json['tier'] as String,
        limits: MeLimits.fromJson(json['limits'] as Map<String, dynamic>),
        subscription:
            MeSubscription.fromJson(json['subscription'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'profile': profile.toJson(),
        'permissions': permissions,
        'tier': tier,
        'limits': limits.toJson(),
        'subscription': subscription.toJson(),
      };
}

/// Result of loading `/me` from the network or from offline cache.
@immutable
class MeLoadSnapshot {
  const MeLoadSnapshot({required this.me, this.fromCache = false});

  final MeResponse me;
  final bool fromCache;
}
