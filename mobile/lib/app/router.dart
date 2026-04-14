import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/auth_state.dart';
import '../core/location_onboarding.dart';
import '../core/product_analytics_nav_observers.dart';
import '../core/shared_preferences_provider.dart';
import 'splash_screen.dart';
import '../features/auth/presentation/location_onboarding_screen.dart';
import '../features/auth/presentation/otp_screen.dart';
import '../features/auth/presentation/phone_screen.dart';
import '../features/auth/presentation/setup_name_screen.dart';
import '../features/home/presentation/map_home_screen.dart';
import '../features/me/presentation/profile_screen.dart';
import '../features/places/presentation/places_search_screen.dart';
import '../features/me/data/me_dto.dart';
import '../features/me/presentation/me_notifier.dart';
import '../features/me/presentation/profile_edit_screen.dart';
import '../features/places/presentation/broadcast_screen.dart';
import '../features/places/presentation/watch_screen.dart';
import '../features/subscription/presentation/checkout_webview_screen.dart';
import '../features/subscription/presentation/plans_screen.dart';
import '../features/saved_lists/presentation/saved_list_editor_screen.dart';
import '../features/saved_lists/presentation/saved_list_import_screen.dart';
import '../features/saved_lists/presentation/saved_list_scan_screen.dart';
import '../features/saved_lists/presentation/saved_lists_library_screen.dart';

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
  '/home': ['woleh.place.watch', 'woleh.place.broadcast'],
  '/map': ['woleh.place.watch', 'woleh.place.broadcast'],
};

/// Paths where the user must have watch **or** broadcast (prefix match).
const _permissionPrefixGuardsAny = <String, List<String>>{
  '/saved-lists': ['woleh.place.watch', 'woleh.place.broadcast'],
};

/// Redirect destination for authenticated users missing a required permission.
const _kUpgradeRedirect = '/plans';

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final notifier = _RouterNotifier(ref);
  final navObservers = ref.watch(productAnalyticsNavigatorObserversProvider);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    observers: navObservers,
    routes: [
      GoRoute(
        path: '/splash',
        name: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth/phone',
        name: '/auth/phone',
        builder: (_, __) => const PhoneScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        name: '/auth/otp',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return OtpScreen(
            phone: extra['phone'] as String,
            expiresInSeconds: extra['expiresInSeconds'] as int,
            productAnalyticsConsent: extra['productAnalyticsConsent'] as bool? ?? true,
          );
        },
      ),
      GoRoute(
        path: '/auth/setup-name',
        name: '/auth/setup-name',
        builder: (_, __) => const SetupNameScreen(),
      ),
      GoRoute(
        path: '/auth/location-intro',
        name: '/auth/location-intro',
        builder: (_, __) => const LocationOnboardingScreen(),
      ),
      GoRoute(
        path: '/home',
        name: '/home',
        builder: (_, __) => const MapHomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: '/profile',
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/places/search',
        name: '/places/search',
        builder: (_, __) => const PlacesSearchScreen(),
      ),
      GoRoute(
        path: '/saved-lists',
        name: '/saved-lists',
        builder: (_, __) => const SavedListsLibraryScreen(),
      ),
      GoRoute(
        path: '/saved-lists/create',
        name: '/saved-lists/create',
        builder: (_, __) => const SavedListEditorScreen(),
      ),
      GoRoute(
        path: '/saved-lists/edit/:id',
        name: '/saved-lists/edit',
        builder: (_, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null) {
            return const SavedListsLibraryScreen();
          }
          return SavedListEditorScreen(listId: id);
        },
      ),
      GoRoute(
        path: '/saved-lists/scan',
        name: '/saved-lists/scan',
        builder: (_, __) => const SavedListScanScreen(),
      ),
      GoRoute(
        path: '/saved-lists/import',
        name: '/saved-lists/import',
        builder: (_, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          if (token.isEmpty) {
            return const SavedListsLibraryScreen();
          }
          return SavedListImportScreen(token: token);
        },
      ),
      GoRoute(path: '/map', redirect: (_, __) => '/home'),
      GoRoute(
        path: '/me/edit',
        name: '/me/edit',
        builder: (_, __) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: '/plans',
        name: '/plans',
        builder: (_, __) => const PlansScreen(),
      ),
      GoRoute(
        path: '/watch',
        name: '/watch',
        builder: (_, __) => const WatchScreen(),
      ),
      GoRoute(
        path: '/broadcast',
        name: '/broadcast',
        builder: (_, __) => const BroadcastScreen(),
      ),
      GoRoute(
        path: '/checkout/:planId',
        name: 'checkout',
        builder: (_, state) =>
            CheckoutWebViewScreen(planId: state.pathParameters['planId']!),
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

  /// Map home when the user has watch or broadcast; otherwise profile (free tier).
  /// Map-eligible users who have not completed [LocationOnboardingScreen] go there first.
  /// Null while [meNotifierProvider] is still loading so splash can wait.
  String? _authenticatedLandingLocation() {
    final meAsync = _ref.read(meNotifierProvider);
    if (meAsync.isLoading) return null;
    final permissions =
        meAsync.valueOrNull?.me.permissions ?? const <String>[];
    final canUseMap = permissions.contains('woleh.place.watch') ||
        permissions.contains('woleh.place.broadcast');
    if (!canUseMap) return '/profile';
    final introDone = _ref.read(sharedPreferencesProvider).getBool(
          kLocationOnboardingCompletedKey,
        ) ??
        false;
    if (!introDone) return '/auth/location-intro';
    return '/home';
  }

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

    // Auth resolved — leave splash once [/me] is ready so we can land on map or profile.
    if (location == '/splash') {
      if (!isAuthenticated) return '/auth/phone';
      final target = _authenticatedLandingLocation();
      if (target == null) return null;
      return target;
    }

    // Unauthenticated users must stay on auth routes.
    if (!isAuthenticated && !location.startsWith('/auth')) {
      return '/auth/phone';
    }

    // Authenticated users skip phone/otp entry — but are allowed on
    // /auth/setup-name (signup name-entry step after first token issuance).
    if (isAuthenticated &&
        (location == '/auth/phone' || location == '/auth/otp')) {
      final target = _authenticatedLandingLocation();
      if (target == null) return '/splash';
      return target;
    }

    // Map-eligible users must complete location intro once before /home.
    if (isAuthenticated && location == '/home') {
      final meAsync = _ref.read(meNotifierProvider);
      if (meAsync.isLoading) return null;
      final permissions =
          meAsync.valueOrNull?.me.permissions ?? const <String>[];
      final canUseMap = permissions.contains('woleh.place.watch') ||
          permissions.contains('woleh.place.broadcast');
      if (canUseMap) {
        final introDone = _ref.read(sharedPreferencesProvider).getBool(
              kLocationOnboardingCompletedKey,
            ) ??
            false;
        if (!introDone) return '/auth/location-intro';
      }
    }

    if (isAuthenticated && location == '/auth/location-intro') {
      final meAsync = _ref.read(meNotifierProvider);
      if (!meAsync.isLoading) {
        final permissions =
            meAsync.valueOrNull?.me.permissions ?? const <String>[];
        final canUseMap = permissions.contains('woleh.place.watch') ||
            permissions.contains('woleh.place.broadcast');
        if (!canUseMap) return '/profile';
        final introDone = _ref.read(sharedPreferencesProvider).getBool(
              kLocationOnboardingCompletedKey,
            ) ??
            false;
        if (introDone) return '/home';
      }
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
      if (requiredAny != null && !requiredAny.any(permissions.contains)) {
        return _kUpgradeRedirect;
      }

      for (final e in _permissionPrefixGuardsAny.entries) {
        final prefix = e.key;
        if (location == prefix || location.startsWith('$prefix/')) {
          if (!e.value.any(permissions.contains)) {
            return _kUpgradeRedirect;
          }
          break;
        }
      }
    }

    return null;
  }
}
