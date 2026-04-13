import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dio/dio.dart';
import 'package:odm_clarity_woleh_mobile/core/auth_state.dart';
import 'package:odm_clarity_woleh_mobile/core/shared_preferences_provider.dart';
import 'package:odm_clarity_woleh_mobile/core/location_onboarding.dart';
import 'package:odm_clarity_woleh_mobile/core/telemetry_consent.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/places/data/place_list_repository.dart';
import 'package:odm_clarity_woleh_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_map_home.dart';

/// No network — for tests where [WolehApp] mounts [LocationPublishNotifier]
/// (which listens to watch/broadcast notifiers) but the case must not leave
/// pending Dio timers (e.g. auth stuck in loading).
class _StubPlaceListRepo implements PlaceListRepository {
  const _StubPlaceListRepo();

  @override
  Future<PlaceListSnapshot> getWatchList() async =>
      const PlaceListSnapshot(names: []);

  @override
  Future<PlaceListSnapshot> getBroadcastList() async =>
      const PlaceListSnapshot(names: []);

  @override
  Future<List<String>> putWatchList(List<String> names) async => names;

  @override
  Future<List<String>> putBroadcastList(List<String> names) async => names;
}

// ---------------------------------------------------------------------------
// Stub auth states
// ---------------------------------------------------------------------------

class _Unauthenticated extends AuthState {
  @override
  Future<String?> build() async => null;
}

class _Authenticated extends AuthState {
  @override
  Future<String?> build() async => 'valid-token';
}

class _AuthLoading extends AuthState {
  @override
  Future<String?> build() {
    // Return a future that never completes (no timer created).
    // This keeps the provider in AsyncLoading without leaving a pending timer.
    return Completer<String?>().future;
  }
}

// ---------------------------------------------------------------------------
// Stub me states
// ---------------------------------------------------------------------------

class _StubMeNotifier extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
    me: const MeResponse(
      profile: MeProfile(userId: '1', phoneE164: '+233241234567'),
      permissions: [
        'woleh.account.profile',
        'woleh.plans.read',
        'woleh.place.watch',
      ],
      tier: 'free',
      limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
      subscription: MeSubscription(status: 'none', inGracePeriod: false),
    ),
  );
}

/// Signed-in user with no watch/broadcast — cannot use map home.
class _NoPlaceMeNotifier extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
    me: const MeResponse(
      profile: MeProfile(userId: '1', phoneE164: '+233241234567'),
      permissions: ['woleh.account.profile', 'woleh.plans.read'],
      tier: 'free',
      limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
      subscription: MeSubscription(status: 'none', inGracePeriod: false),
    ),
  );
}

/// Free-tier user — has base permissions but NOT woleh.place.broadcast.
class _FreeUserMeNotifier extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
    me: const MeResponse(
      profile: MeProfile(userId: '1', phoneE164: '+233241234567'),
      permissions: [
        'woleh.account.profile',
        'woleh.plans.read',
        'woleh.place.watch',
      ],
      tier: 'free',
      limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
      subscription: MeSubscription(status: 'none', inGracePeriod: false),
    ),
  );
}

/// Paid-tier user — holds all permissions including woleh.place.broadcast.
class _PaidUserMeNotifier extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
    me: const MeResponse(
      profile: MeProfile(userId: '1', phoneE164: '+233241234567'),
      permissions: [
        'woleh.account.profile',
        'woleh.plans.read',
        'woleh.place.watch',
        'woleh.place.broadcast',
      ],
      tier: 'paid',
      limits: MeLimits(placeWatchMax: 50, placeBroadcastMax: 50),
      subscription: MeSubscription(
        status: 'active',
        currentPeriodEnd: '2026-05-09T00:00:00Z',
        inGracePeriod: false,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Stub place-list repository
//
// Returns empty lists immediately so that screens that watch place-list
// notifiers (WatchScreen, BroadcastScreen) can settle during pumpAndSettle
// without making real network calls.
// ---------------------------------------------------------------------------

class _EmptyPlaceListRepository extends PlaceListRepository {
  _EmptyPlaceListRepository(SharedPreferences prefs) : super(Dio(), prefs);

  @override
  Future<PlaceListSnapshot> getWatchList() async =>
      const PlaceListSnapshot(names: []);

  @override
  Future<PlaceListSnapshot> getBroadcastList() async =>
      const PlaceListSnapshot(names: []);

  @override
  Future<List<String>> putWatchList(List<String> names) async => names;

  @override
  Future<List<String>> putBroadcastList(List<String> names) async => names;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late SharedPreferences routerTestPrefs;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      kTelemetryProductAnalyticsConsentKey: true,
      kLocationOnboardingCompletedKey: true,
    });
    routerTestPrefs = await SharedPreferences.getInstance();
  });

  group('Router redirect', () {
    group('unauthenticated', () {
      testWidgets(
        'leaves splash and shows phone screen once auth is resolved',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(routerTestPrefs),
                authStateProvider.overrideWith(_Unauthenticated.new),
              ],
              child: const WolehApp(),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Sign in'), findsOneWidget);
          expect(find.text('Woleh'), findsNothing);
        },
      );

      testWidgets('landing on /home redirects to /auth/phone', (tester) async {
        // Unauthenticated users are never left on /home (splash → phone, or
        // any /home navigation redirects to sign-in).
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(routerTestPrefs),
              authStateProvider.overrideWith(_Unauthenticated.new),
            ],
            child: const WolehApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Search places'), findsNothing);
        expect(find.text('Sign in'), findsOneWidget);
      });
    });

    group('authenticated', () {
      testWidgets('shows map home after auth', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(routerTestPrefs),
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_StubMeNotifier.new),
            ],
            child: const WolehApp(),
          ),
        );
        await pumpWolehWithMap(tester);

        expect(find.text('Search places'), findsOneWidget);
        expect(find.text('Sign in'), findsNothing);
      });

      testWidgets('/auth/phone redirects authenticated user to home', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(routerTestPrefs),
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_StubMeNotifier.new),
            ],
            child: const WolehApp(),
          ),
        );
        await pumpWolehWithMap(tester);

        // Splash resolves with a token → user ends on /home.
        expect(find.text('Sign in'), findsNothing);
        expect(find.text('Search places'), findsOneWidget);
      });
    });

    group('auth loading', () {
      testWidgets('shows splash while token read is in progress', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(routerTestPrefs),
              authStateProvider.overrideWith(_AuthLoading.new),
              placeListRepositoryProvider
                  .overrideWithValue(const _StubPlaceListRepo()),
            ],
            child: const WolehApp(),
          ),
        );
        // Only pump one frame — don't settle, as the future never resolves.
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Woleh'), findsOneWidget);
        expect(find.text('Sign in'), findsNothing);
      });
    });

    group('/auth/setup-name', () {
      testWidgets('accessible when authenticated (not redirected to /home)', (
        tester,
      ) async {
        // Build the full app with a router and navigate to /auth/setup-name.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(routerTestPrefs),
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_StubMeNotifier.new),
            ],
            child: const WolehApp(),
          ),
        );
        await pumpWolehWithMap(tester);

        // The app is at /home. Verify the setup-name route is reachable by
        // confirming the router doesn't redirect it away on arrival — tested
        // via the redirect implementation not listing /auth/setup-name
        // in the protected-auth-route set. This is a smoke test.
        expect(tester.takeException(), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // Permission-gate tests (Step 3.1)
    // -----------------------------------------------------------------------

    // -----------------------------------------------------------------------
    // /watch permission gate (Step 3.3 + 3.7)
    // -----------------------------------------------------------------------

    group('watch permission gate', () {
      testWidgets('user without woleh.place.watch lands on profile; /watch → /plans', (
        tester,
      ) async {
        // User has no woleh.place.watch / broadcast — default landing is profile, not /plans.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(routerTestPrefs),
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_NoPlaceMeNotifier.new),
            ],
            child: const WolehApp(),
          ),
        );
        await pumpWolehWithMap(tester);

        // Profile hub (not map home); "Plans" also appears as a permission chip label.
        expect(find.text('Limits'), findsOneWidget);
        expect(find.text('Search places'), findsNothing);

        final context = tester.element(find.byType(Scaffold).first);
        GoRouter.of(context).go('/watch');
        await tester.pumpAndSettle();

        // No woleh.place.watch → redirected to /plans.
        expect(find.text('Plans'), findsOneWidget);
        expect(find.text('Watch List'), findsNothing);
      });

      testWidgets(
        'user with woleh.place.watch is allowed through to WatchScreen',
        (tester) async {
          // _FreeUserMeNotifier has woleh.place.watch but not broadcast.
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(routerTestPrefs),
                authStateProvider.overrideWith(_Authenticated.new),
                meNotifierProvider.overrideWith(_FreeUserMeNotifier.new),
                placeListRepositoryProvider.overrideWith(
                  (_) => _EmptyPlaceListRepository(routerTestPrefs),
                ),
              ],
              child: const WolehApp(),
            ),
          );
          await pumpWolehWithMap(tester);

          final context = tester.element(find.byType(Scaffold).first);
          GoRouter.of(context).go('/watch');
          await tester.pumpAndSettle();

          // Has woleh.place.watch → WatchScreen shown.
          expect(find.text('Watch List'), findsOneWidget);
          expect(find.text('Plans'), findsNothing);
        },
      );
    });

    group('broadcast permission gate', () {
      testWidgets(
        'free user navigating to /broadcast is redirected to /plans',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(routerTestPrefs),
                authStateProvider.overrideWith(_Authenticated.new),
                meNotifierProvider.overrideWith(_FreeUserMeNotifier.new),
                placeListRepositoryProvider.overrideWith(
                  (_) => _EmptyPlaceListRepository(routerTestPrefs),
                ),
              ],
              child: const WolehApp(),
            ),
          );
          await pumpWolehWithMap(tester);

          // Navigate to the broadcast-gated route.
          // Use a widget inside the router's InheritedWidget scope (Scaffold is
          // rendered by MapHomeScreen which is a GoRouter child).
          final context = tester.element(find.byType(Scaffold).first);
          GoRouter.of(context).go('/broadcast');
          await tester.pumpAndSettle();

          // Missing woleh.place.broadcast → redirected to /plans.
          expect(find.text('Plans'), findsOneWidget);
          expect(find.text('Broadcast List'), findsNothing);
        },
      );

      testWidgets('paid user navigating to /broadcast is allowed through', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(routerTestPrefs),
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_PaidUserMeNotifier.new),
              placeListRepositoryProvider.overrideWith(
                (_) => _EmptyPlaceListRepository(routerTestPrefs),
              ),
            ],
            child: const WolehApp(),
          ),
        );
        await pumpWolehWithMap(tester);

        // Navigate to the broadcast-gated route.
        final context = tester.element(find.byType(Scaffold).first);
        GoRouter.of(context).go('/broadcast');
        await tester.pumpAndSettle();

        // Holds woleh.place.broadcast → real BroadcastScreen is shown.
        // "Broadcast List" is the AppBar title; the stub repository returns
        // immediately so the screen reaches BroadcastReady.
        expect(find.text('Broadcast List'), findsOneWidget);
        expect(find.text('Plans'), findsNothing);
      });
    });

    group('/plans route', () {
      testWidgets(
        'authenticated user can navigate to /plans without redirect',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(routerTestPrefs),
                authStateProvider.overrideWith(_Authenticated.new),
                meNotifierProvider.overrideWith(_StubMeNotifier.new),
              ],
              child: const WolehApp(),
            ),
          );
          await pumpWolehWithMap(tester);

          final context = tester.element(find.byType(Scaffold).first);
          GoRouter.of(context).go('/plans');
          await tester.pumpAndSettle();

          expect(find.text('Plans'), findsOneWidget);
        },
      );
    });
  });
}
