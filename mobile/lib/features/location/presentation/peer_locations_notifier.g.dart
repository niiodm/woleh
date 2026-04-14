// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'peer_locations_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$peerLocationsNotifierHash() =>
    r'e3793280814e4eb15cd25dde9438655fff3f659b';

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
///
/// Copied from [PeerLocationsNotifier].
@ProviderFor(PeerLocationsNotifier)
final peerLocationsNotifierProvider =
    NotifierProvider<PeerLocationsNotifier, Map<String, PeerLocation>>.internal(
      PeerLocationsNotifier.new,
      name: r'peerLocationsNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$peerLocationsNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$PeerLocationsNotifier = Notifier<Map<String, PeerLocation>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
