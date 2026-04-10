// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ws_client.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$wsClientHash() => r'42c2bfcdce03c35fa1b40bdac070323b3e5baf79';

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
///
/// Copied from [WsClient].
@ProviderFor(WsClient)
final wsClientProvider = NotifierProvider<WsClient, void>.internal(
  WsClient.new,
  name: r'wsClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$wsClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$WsClient = Notifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
