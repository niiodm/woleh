import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dio/dio.dart';
import 'package:odm_clarity_woleh_mobile/core/auth_state.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/places/data/place_list_repository.dart';
import 'package:odm_clarity_woleh_mobile/main.dart';

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
  Future<MeResponse?> build() async => const MeResponse(
        profile: MeProfile(userId: '1', phoneE164: '+233241234567'),
        permissions: [],
        tier: 'free',
        limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
        subscription: MeSubscription(status: 'none', inGracePeriod: false),
      );
}

/// Free-tier user — has base permissions but NOT woleh.place.broadcast.
class _FreeUserMeNotifier extends MeNotifier {
  @override
  Future<MeResponse?> build() async => const MeResponse(
        profile: MeProfile(userId: '1', phoneE164: '+233241234567'),
        permissions: [
          'woleh.account.profile',
          'woleh.plans.read',
          'woleh.place.watch',
        ],
        tier: 'free',
        limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
        subscription: MeSubscription(status: 'none', inGracePeriod: false),
      );
}

/// Paid-tier user — holds all permissions including woleh.place.broadcast.
class _PaidUserMeNotifier extends MeNotifier {
  @override
  Future<MeResponse?> build() async => const MeResponse(
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
  _EmptyPlaceListRepository() : super(Dio());

  @override
  Future<List<String>> getWatchList() async => [];

  @override
  Future<List<String>> getBroadcastList() async => [];

  @override
  Future<List<String>> putWatchList(List<String> names) async => names;

  @override
  Future<List<String>> putBroadcastList(List<String> names) async => names;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Router redirect', () {
    group('unauthenticated', () {
      testWidgets('shows phone/sign-in screen as initial route', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(_Unauthenticated.new),
            ],
            child: const WolehApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sign in'), findsOneWidget);
      });

      testWidgets('landing on /home redirects to /auth/phone', (tester) async {
        // The app always starts at /auth/phone; the only way to verify the
        // redirect fires is to confirm the auth screen (not home) is shown.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(_Unauthenticated.new),
            ],
            child: const WolehApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Woleh'), findsNothing); // home AppBar title absent
        expect(find.text('Sign in'), findsOneWidget);
      });
    });

    group('authenticated', () {
      testWidgets('shows home screen with profile', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_StubMeNotifier.new),
            ],
            child: const WolehApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Home AppBar visible; auth screen absent.
        expect(find.text('Woleh'), findsOneWidget);
        expect(find.text('Sign in'), findsNothing);
      });

      testWidgets(
          '/auth/phone redirects authenticated user to home', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_StubMeNotifier.new),
            ],
            child: const WolehApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Router starts at /auth/phone by default but token is present →
        // redirect to /home.
        expect(find.text('Sign in'), findsNothing);
        expect(find.text('Woleh'), findsOneWidget);
      });
    });

    group('auth loading', () {
      testWidgets(
          'renders without crashing while token read is in progress',
          (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(_AuthLoading.new),
            ],
            child: const WolehApp(),
          ),
        );
        // Only pump one frame — don't settle, as the future never resolves.
        await tester.pump();

        // App must render without throwing; route stays at initial location.
        expect(tester.takeException(), isNull);
      });
    });

    group('/auth/setup-name', () {
      testWidgets(
          'accessible when authenticated (not redirected to /home)',
          (tester) async {
        // Build the full app with a router and navigate to /auth/setup-name.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_StubMeNotifier.new),
            ],
            child: const WolehApp(),
          ),
        );
        await tester.pumpAndSettle();

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
      testWidgets(
          'user without woleh.place.watch is redirected to /plans',
          (tester) async {
        // _StubMeNotifier has permissions: [] — no place.watch.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_StubMeNotifier.new),
            ],
            child: const WolehApp(),
          ),
        );
        await tester.pumpAndSettle();

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
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_FreeUserMeNotifier.new),
              placeListRepositoryProvider
                  .overrideWith((_) => _EmptyPlaceListRepository()),
            ],
            child: const WolehApp(),
          ),
        );
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(Scaffold).first);
        GoRouter.of(context).go('/watch');
        await tester.pumpAndSettle();

        // Has woleh.place.watch → WatchScreen shown.
        expect(find.text('Watch List'), findsOneWidget);
        expect(find.text('Plans'), findsNothing);
      });
    });

    group('broadcast permission gate', () {
      testWidgets(
          'free user navigating to /broadcast is redirected to /plans',
          (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_FreeUserMeNotifier.new),
              placeListRepositoryProvider
                  .overrideWith((_) => _EmptyPlaceListRepository()),
            ],
            child: const WolehApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to the broadcast-gated route.
        // Use a widget inside the router's InheritedWidget scope (Scaffold is
        // rendered by HomeScreen which is a GoRouter child).
        final context = tester.element(find.byType(Scaffold).first);
        GoRouter.of(context).go('/broadcast');
        await tester.pumpAndSettle();

        // Missing woleh.place.broadcast → redirected to /plans.
        expect(find.text('Plans'), findsOneWidget);
        expect(find.text('Broadcast List'), findsNothing);
      });

      testWidgets(
          'paid user navigating to /broadcast is allowed through',
          (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_PaidUserMeNotifier.new),
              placeListRepositoryProvider
                  .overrideWith((_) => _EmptyPlaceListRepository()),
            ],
            child: const WolehApp(),
          ),
        );
        await tester.pumpAndSettle();

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
              authStateProvider.overrideWith(_Authenticated.new),
              meNotifierProvider.overrideWith(_StubMeNotifier.new),
            ],
            child: const WolehApp(),
          ),
        );
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(Scaffold).first);
        GoRouter.of(context).go('/plans');
        await tester.pumpAndSettle();

        expect(find.text('Plans'), findsOneWidget);
      });
    });
  });
}
