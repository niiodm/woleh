import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/app_error.dart';
import '../../../core/auth_state.dart';
import '../data/me_dto.dart';
import '../data/me_repository.dart';

part 'me_notifier.g.dart';

/// Holds the current user's profile and entitlements.
///
/// Lifecycle:
/// - Rebuilds whenever [authStateProvider] changes (token set or cleared).
/// - When a token is present, fetches `GET /me` automatically.
/// - A **401** response means the stored token is expired or revoked:
///   the notifier calls [AuthState.signOut], which clears the token and
///   triggers the router redirect back to the auth flow.
/// - Consumers can call [refresh] after a profile update to re-fetch.
@riverpod
class MeNotifier extends _$MeNotifier {
  @override
  Future<MeResponse?> build() async {
    // Re-run this provider whenever the auth token changes.
    final token = await ref.watch(authStateProvider.future);
    if (token == null) return null;

    try {
      return await ref.read(meRepositoryProvider).getMe();
    } catch (e) {
      final appError =
          e is DioException && e.error is AppError ? e.error as AppError : null;
      if (appError is UnauthorizedError) {
        // Token is expired or invalid — sign out and let the router redirect.
        await ref.read(authStateProvider.notifier).signOut();
        return null;
      }
      rethrow;
    }
  }

  /// Re-fetches `GET /me` and updates state in place.
  /// Call this after a successful profile patch to reflect the new name.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
