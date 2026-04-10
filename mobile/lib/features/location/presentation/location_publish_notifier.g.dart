// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_publish_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$locationPublishNotifierHash() =>
    r'd567dd3615bbc8021107096726307c370499f254';

/// Foreground GPS → throttled `POST /api/v1/me/location` ([`MAP_LIVE_LOCATION_PLAN.md`](../../../../../docs/MAP_LIVE_LOCATION_PLAN.md) §4.3).
///
/// Subscribes only when the user is signed in, has watch or broadcast permission,
/// and `locationSharingEnabled` is true. Pauses when the app is not in a
/// foreground-eligible lifecycle state.
///
/// Copied from [LocationPublishNotifier].
@ProviderFor(LocationPublishNotifier)
final locationPublishNotifierProvider =
    NotifierProvider<LocationPublishNotifier, void>.internal(
      LocationPublishNotifier.new,
      name: r'locationPublishNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$locationPublishNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$LocationPublishNotifier = Notifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
