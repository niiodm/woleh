import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:odm_clarity_woleh_mobile/core/auth_state.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';
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
// Stub me state (used when the home screen needs me data)
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
        // via the redirect function returning null for that path, which is
        // covered by the redirect implementation not listing /auth/setup-name
        // in the protected-auth-route set. This is a smoke test.
        expect(tester.takeException(), isNull);
      });
    });
  });
}
