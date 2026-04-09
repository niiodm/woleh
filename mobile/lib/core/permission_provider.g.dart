// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'permission_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$permissionsHash() => r'4a2d8b8b7f3755888d72c2c30eceec0275ebe894';

/// Derives the current user's effective permission strings from [meNotifierProvider].
///
/// Returns an empty list while [meNotifierProvider] is loading or unauthenticated.
/// Stays in sync automatically whenever [meNotifierProvider] reloads (e.g. after
/// a successful checkout).
///
/// Copied from [permissions].
@ProviderFor(permissions)
final permissionsProvider = Provider<List<String>>.internal(
  permissions,
  name: r'permissionsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$permissionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PermissionsRef = ProviderRef<List<String>>;
String _$hasPermissionHash() => r'ec6a9cbf113e31473f94e622b40473220d65f381';

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

/// Returns `true` when the authenticated user holds [permission].
///
/// Usage in widgets: `ref.watch(hasPermissionProvider('woleh.place.broadcast'))`
///
/// Copied from [hasPermission].
@ProviderFor(hasPermission)
const hasPermissionProvider = HasPermissionFamily();

/// Returns `true` when the authenticated user holds [permission].
///
/// Usage in widgets: `ref.watch(hasPermissionProvider('woleh.place.broadcast'))`
///
/// Copied from [hasPermission].
class HasPermissionFamily extends Family<bool> {
  /// Returns `true` when the authenticated user holds [permission].
  ///
  /// Usage in widgets: `ref.watch(hasPermissionProvider('woleh.place.broadcast'))`
  ///
  /// Copied from [hasPermission].
  const HasPermissionFamily();

  /// Returns `true` when the authenticated user holds [permission].
  ///
  /// Usage in widgets: `ref.watch(hasPermissionProvider('woleh.place.broadcast'))`
  ///
  /// Copied from [hasPermission].
  HasPermissionProvider call(String permission) {
    return HasPermissionProvider(permission);
  }

  @override
  HasPermissionProvider getProviderOverride(
    covariant HasPermissionProvider provider,
  ) {
    return call(provider.permission);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'hasPermissionProvider';
}

/// Returns `true` when the authenticated user holds [permission].
///
/// Usage in widgets: `ref.watch(hasPermissionProvider('woleh.place.broadcast'))`
///
/// Copied from [hasPermission].
class HasPermissionProvider extends AutoDisposeProvider<bool> {
  /// Returns `true` when the authenticated user holds [permission].
  ///
  /// Usage in widgets: `ref.watch(hasPermissionProvider('woleh.place.broadcast'))`
  ///
  /// Copied from [hasPermission].
  HasPermissionProvider(String permission)
    : this._internal(
        (ref) => hasPermission(ref as HasPermissionRef, permission),
        from: hasPermissionProvider,
        name: r'hasPermissionProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$hasPermissionHash,
        dependencies: HasPermissionFamily._dependencies,
        allTransitiveDependencies:
            HasPermissionFamily._allTransitiveDependencies,
        permission: permission,
      );

  HasPermissionProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.permission,
  }) : super.internal();

  final String permission;

  @override
  Override overrideWith(bool Function(HasPermissionRef provider) create) {
    return ProviderOverride(
      origin: this,
      override: HasPermissionProvider._internal(
        (ref) => create(ref as HasPermissionRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        permission: permission,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<bool> createElement() {
    return _HasPermissionProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is HasPermissionProvider && other.permission == permission;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, permission.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin HasPermissionRef on AutoDisposeProviderRef<bool> {
  /// The parameter `permission` of this provider.
  String get permission;
}

class _HasPermissionProviderElement extends AutoDisposeProviderElement<bool>
    with HasPermissionRef {
  _HasPermissionProviderElement(super.provider);

  @override
  String get permission => (origin as HasPermissionProvider).permission;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
