import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/me/presentation/me_notifier.dart';

part 'permission_provider.g.dart';

/// Derives the current user's effective permission strings from [meNotifierProvider].
///
/// Returns an empty list while [meNotifierProvider] is loading or unauthenticated.
/// Stays in sync automatically whenever [meNotifierProvider] reloads (e.g. after
/// a successful checkout).
@Riverpod(keepAlive: true)
List<String> permissions(Ref ref) {
  final meAsync = ref.watch(meNotifierProvider);
  return meAsync.valueOrNull?.me.permissions ?? const [];
}

/// Returns `true` when the authenticated user holds [permission].
///
/// Usage in widgets: `ref.watch(hasPermissionProvider('woleh.place.broadcast'))`
@riverpod
bool hasPermission(Ref ref, String permission) {
  return ref.watch(permissionsProvider).contains(permission);
}
