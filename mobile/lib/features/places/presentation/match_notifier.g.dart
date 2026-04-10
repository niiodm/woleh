// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$matchNotifierHash() => r'8a1ff9755fb33cb6e3237b6c9c1f2e7d97221316';

/// Accumulates incoming [MatchMessage]s from the WebSocket stream.
///
/// State is a list of up to [_cap] most-recent matches (newest first).
/// Clears automatically on sign-out.
///
/// Copied from [MatchNotifier].
@ProviderFor(MatchNotifier)
final matchNotifierProvider =
    NotifierProvider<MatchNotifier, List<MatchMessage>>.internal(
      MatchNotifier.new,
      name: r'matchNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$matchNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$MatchNotifier = Notifier<List<MatchMessage>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
