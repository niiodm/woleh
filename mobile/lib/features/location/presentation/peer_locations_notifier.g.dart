// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'peer_locations_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$peerLocationsNotifierHash() =>
    r'0f973a7358927128aae4fce383fc42e8cb6c53fd';

/// Last-known [PeerLocation] per peer user id from WebSocket `peer_location`.
///
/// - Updates on [PeerLocationMessage]; removes a key on [PeerLocationRevokedMessage].
/// - Incoming peer fixes are shown whenever received; **local** [MeProfile.locationSharingEnabled]
///   only controls publishing (`POST /me/location`), not whether you can see matched peers.
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
