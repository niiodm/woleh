// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'telemetry_consent_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$productAnalyticsConsentGrantedHash() =>
    r'804bcfdde4214c6d41ec3215f1e757a60bad54e2';

/// Whether custom events, user id, and automatic screen views may run.
///
/// Copied from [productAnalyticsConsentGranted].
@ProviderFor(productAnalyticsConsentGranted)
final productAnalyticsConsentGrantedProvider = Provider<bool>.internal(
  productAnalyticsConsentGranted,
  name: r'productAnalyticsConsentGrantedProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$productAnalyticsConsentGrantedHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ProductAnalyticsConsentGrantedRef = ProviderRef<bool>;
String _$telemetryConsentHash() => r'bac7b06f43862cea0182f3ed18bf905ed43dcc13';

/// Stored user choice: `null` = not asked, `true` = allowed, `false` = declined.
///
/// Copied from [TelemetryConsent].
@ProviderFor(TelemetryConsent)
final telemetryConsentProvider =
    NotifierProvider<TelemetryConsent, bool?>.internal(
      TelemetryConsent.new,
      name: r'telemetryConsentProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$telemetryConsentHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$TelemetryConsent = Notifier<bool?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
