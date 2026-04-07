import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/auth_state.dart';
import '../features/auth/presentation/otp_screen.dart';
import '../features/auth/presentation/phone_screen.dart';
import '../features/auth/presentation/setup_name_screen.dart';
import '../features/home/presentation/home_screen.dart';

part 'router.g.dart';

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final notifier = _RouterNotifier(ref);
  return GoRouter(
    initialLocation: '/auth/phone',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(
        path: '/auth/phone',
        builder: (_, __) => const PhoneScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return OtpScreen(
            phone: extra['phone'] as String,
            expiresInSeconds: extra['expiresInSeconds'] as int,
          );
        },
      ),
      GoRoute(
        path: '/auth/setup-name',
        builder: (_, __) => const SetupNameScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
    ],
  );
}

/// Bridges Riverpod auth state changes into GoRouter's [Listenable] refresh
/// so the router re-evaluates its redirect whenever the token changes.
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AsyncValue<String?>>(authStateProvider, (_, __) {
      notifyListeners();
    });
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final authAsync = _ref.read(authStateProvider);

    // Don't redirect while the token is still being loaded from secure storage.
    if (authAsync.isLoading) return null;

    final isAuthenticated = authAsync.valueOrNull != null;
    final location = state.matchedLocation;

    // Unauthenticated users must stay on auth routes.
    if (!isAuthenticated && !location.startsWith('/auth')) return '/auth/phone';

    // Authenticated users skip phone/otp entry — but are allowed on
    // /auth/setup-name (signup name-entry step after first token issuance).
    if (isAuthenticated &&
        (location == '/auth/phone' || location == '/auth/otp')) {
      return '/home';
    }

    return null;
  }
}
