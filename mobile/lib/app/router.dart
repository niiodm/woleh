import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/auth_state.dart';
import 'splash_screen.dart';
import '../features/auth/presentation/otp_screen.dart';
import '../features/auth/presentation/phone_screen.dart';
import '../features/auth/presentation/setup_name_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/location/presentation/live_map_screen.dart';
import '../features/me/data/me_dto.dart';
import '../features/me/presentation/me_notifier.dart';
import '../features/me/presentation/profile_edit_screen.dart';
import '../features/places/presentation/broadcast_screen.dart';
import '../features/places/presentation/watch_screen.dart';
import '../features/subscription/presentation/checkout_webview_screen.dart';
import '../features/subscription/presentation/plans_screen.dart';

part 'router.g.dart';

/// Routes protected by a specific permission string.
///
/// When an authenticated user navigates to a guarded path without holding the
/// required permission, the router redirects them to [_kUpgradeRedirect].
const _permissionGuards = <String, String>{
  '/watch': 'woleh.place.watch',
  '/broadcast': 'woleh.place.broadcast',
};

/// Routes that require **any** of these permissions (e.g. live map: watch or broadcast).
const _permissionGuardsAny = <String, List<String>>{
  '/map': ['woleh.place.watch', 'woleh.place.broadcast'],
};

/// Redirect destination for authenticated users missing a required permission.
const _kUpgradeRedirect = '/plans';

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final notifier = _RouterNotifier(ref);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
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
      GoRoute(
        path: '/map',
        builder: (_, __) => const LiveMapScreen(),
      ),
      GoRoute(
        path: '/me/edit',
        builder: (_, __) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: '/plans',
        builder: (_, __) => const PlansScreen(),
      ),
      GoRoute(
        path: '/watch',
        builder: (_, __) => const WatchScreen(),
      ),
      GoRoute(
        path: '/broadcast',
        builder: (_, __) => const BroadcastScreen(),
      ),
      GoRoute(
        path: '/checkout/:planId',
        builder: (_, state) => CheckoutWebViewScreen(
          planId: state.pathParameters['planId']!,
        ),
      ),
    ],
  );
}

/// Bridges Riverpod state changes into GoRouter's [Listenable] refresh
/// so the router re-evaluates its redirect whenever the token or the
/// user's entitlements change (e.g. after a successful checkout).
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AsyncValue<String?>>(authStateProvider, (_, __) {
      notifyListeners();
    });
    // Re-evaluate permission guards whenever GET /me resolves or updates.
    _ref.listen<AsyncValue<MeLoadSnapshot?>>(meNotifierProvider, (_, __) {
      notifyListeners();
    });
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final authAsync = _ref.read(authStateProvider);
    final location = state.matchedLocation;

    // While the token is still loading, only [/splash] is shown (avoids flashing
    // /auth/phone before we know if the user is signed in).
    if (authAsync.isLoading) {
      if (location != '/splash') return '/splash';
      return null;
    }

    final isAuthenticated = authAsync.valueOrNull != null;

    // Auth resolved — leave splash immediately.
    if (location == '/splash') {
      return isAuthenticated ? '/home' : '/auth/phone';
    }

    // Unauthenticated users must stay on auth routes.
    if (!isAuthenticated && !location.startsWith('/auth')) {
      return '/auth/phone';
    }

    // Authenticated users skip phone/otp entry — but are allowed on
    // /auth/setup-name (signup name-entry step after first token issuance).
    if (isAuthenticated &&
        (location == '/auth/phone' || location == '/auth/otp')) {
      return '/home';
    }

    // Permission-based route guards (authenticated users only).
    if (isAuthenticated) {
      final meAsync = _ref.read(meNotifierProvider);

      // Defer while entitlements are still loading to avoid a flash redirect.
      if (meAsync.isLoading) return null;

      final permissions =
          meAsync.valueOrNull?.me.permissions ?? const <String>[];
      final requiredPermission = _permissionGuards[location];
      if (requiredPermission != null &&
          !permissions.contains(requiredPermission)) {
        return _kUpgradeRedirect;
      }

      final requiredAny = _permissionGuardsAny[location];
      if (requiredAny != null &&
          !requiredAny.any(permissions.contains)) {
        return _kUpgradeRedirect;
      }
    }

    return null;
  }
}
