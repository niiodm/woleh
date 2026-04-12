// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'otp_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$otpNotifierHash() => r'f292d7ab1b640d02e5fc3f7b4f55e4182de3fa7b';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$OtpNotifier extends BuildlessAutoDisposeNotifier<OtpState> {
  late final String phoneE164;

  OtpState build(String phoneE164);
}

/// Notifier for the OTP entry screen.
///
/// Constructed as a family keyed by [phoneE164] so that the countdown and
/// error state are scoped to one phone session.
///
/// Copied from [OtpNotifier].
@ProviderFor(OtpNotifier)
const otpNotifierProvider = OtpNotifierFamily();

/// Notifier for the OTP entry screen.
///
/// Constructed as a family keyed by [phoneE164] so that the countdown and
/// error state are scoped to one phone session.
///
/// Copied from [OtpNotifier].
class OtpNotifierFamily extends Family<OtpState> {
  /// Notifier for the OTP entry screen.
  ///
  /// Constructed as a family keyed by [phoneE164] so that the countdown and
  /// error state are scoped to one phone session.
  ///
  /// Copied from [OtpNotifier].
  const OtpNotifierFamily();

  /// Notifier for the OTP entry screen.
  ///
  /// Constructed as a family keyed by [phoneE164] so that the countdown and
  /// error state are scoped to one phone session.
  ///
  /// Copied from [OtpNotifier].
  OtpNotifierProvider call(String phoneE164) {
    return OtpNotifierProvider(phoneE164);
  }

  @override
  OtpNotifierProvider getProviderOverride(
    covariant OtpNotifierProvider provider,
  ) {
    return call(provider.phoneE164);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'otpNotifierProvider';
}

/// Notifier for the OTP entry screen.
///
/// Constructed as a family keyed by [phoneE164] so that the countdown and
/// error state are scoped to one phone session.
///
/// Copied from [OtpNotifier].
class OtpNotifierProvider
    extends AutoDisposeNotifierProviderImpl<OtpNotifier, OtpState> {
  /// Notifier for the OTP entry screen.
  ///
  /// Constructed as a family keyed by [phoneE164] so that the countdown and
  /// error state are scoped to one phone session.
  ///
  /// Copied from [OtpNotifier].
  OtpNotifierProvider(String phoneE164)
    : this._internal(
        () => OtpNotifier()..phoneE164 = phoneE164,
        from: otpNotifierProvider,
        name: r'otpNotifierProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$otpNotifierHash,
        dependencies: OtpNotifierFamily._dependencies,
        allTransitiveDependencies: OtpNotifierFamily._allTransitiveDependencies,
        phoneE164: phoneE164,
      );

  OtpNotifierProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.phoneE164,
  }) : super.internal();

  final String phoneE164;

  @override
  OtpState runNotifierBuild(covariant OtpNotifier notifier) {
    return notifier.build(phoneE164);
  }

  @override
  Override overrideWith(OtpNotifier Function() create) {
    return ProviderOverride(
      origin: this,
      override: OtpNotifierProvider._internal(
        () => create()..phoneE164 = phoneE164,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        phoneE164: phoneE164,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<OtpNotifier, OtpState> createElement() {
    return _OtpNotifierProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is OtpNotifierProvider && other.phoneE164 == phoneE164;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, phoneE164.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin OtpNotifierRef on AutoDisposeNotifierProviderRef<OtpState> {
  /// The parameter `phoneE164` of this provider.
  String get phoneE164;
}

class _OtpNotifierProviderElement
    extends AutoDisposeNotifierProviderElement<OtpNotifier, OtpState>
    with OtpNotifierRef {
  _OtpNotifierProviderElement(super.provider);

  @override
  String get phoneE164 => (origin as OtpNotifierProvider).phoneE164;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
