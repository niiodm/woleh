// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'me_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$meNotifierHash() => r'48cfb41d2cbdcc7c36b3a6a9c461f89e04bd6eba';

/// Holds the current user's profile and entitlements.
///
/// Lifecycle:
/// - Rebuilds whenever [authStateProvider] changes (token set or cleared).
/// - When a token is present, fetches `GET /me` automatically.
/// - A **401** response means the stored token is expired or revoked:
///   the notifier calls [AuthState.signOut], which clears the token and
///   triggers the router redirect back to the auth flow.
/// - Consumers can call [refresh] after a profile update to re-fetch.
///
/// Copied from [MeNotifier].
@ProviderFor(MeNotifier)
final meNotifierProvider =
    AutoDisposeAsyncNotifierProvider<MeNotifier, MeResponse?>.internal(
      MeNotifier.new,
      name: r'meNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$meNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$MeNotifier = AutoDisposeAsyncNotifier<MeResponse?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
