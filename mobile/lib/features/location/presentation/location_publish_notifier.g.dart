// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_publish_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$locationPublishNotifierHash() =>
    r'4dc7d9133dc779ea64ecbe028121eaf65491bb61';

/// Foreground GPS → throttled `POST /api/v1/me/location` ([`MAP_LIVE_LOCATION_PLAN.md`](../../../../../docs/MAP_LIVE_LOCATION_PLAN.md) §4.3).
///
/// Subscribes only when the user is signed in, has watch or broadcast permission,
/// and `locationSharingEnabled` is true. Pauses when the app is not in a
/// foreground-eligible lifecycle state.
///
/// [state] is the latest device fix for map UI (§4.4); cleared when not publishing.
///
/// Copied from [LocationPublishNotifier].
@ProviderFor(LocationPublishNotifier)
final locationPublishNotifierProvider =
    NotifierProvider<LocationPublishNotifier, LocationFix?>.internal(
      LocationPublishNotifier.new,
      name: r'locationPublishNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$locationPublishNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$LocationPublishNotifier = Notifier<LocationFix?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
