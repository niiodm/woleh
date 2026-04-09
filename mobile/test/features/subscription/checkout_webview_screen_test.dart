import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/subscription/presentation/checkout_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/subscription/presentation/checkout_webview_screen.dart';

// ---------------------------------------------------------------------------
// Stub notifiers that pre-set the checkout state
// ---------------------------------------------------------------------------

class _LoadingCheckoutNotifier extends CheckoutNotifier {
  @override
  CheckoutState build() => const CheckoutLoading();

  // Disable auto-start so loading state persists for the test.
  @override
  Future<void> startCheckout(String planId) async {}
}

class _FailedCheckoutNotifier extends CheckoutNotifier {
  @override
  CheckoutState build() =>
      const CheckoutFailed(message: 'Something went wrong. Please try again.');

  @override
  Future<void> startCheckout(String planId) async {}

  @override
  void reset() => state = const CheckoutIdle();
}

class _FreeMeNotifier extends MeNotifier {
  @override
  Future<MeResponse?> build() async => const MeResponse(
        profile: MeProfile(userId: '1', phoneE164: '+233241234567'),
        permissions: ['woleh.account.profile', 'woleh.plans.read'],
        tier: 'free',
        limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
        subscription: MeSubscription(status: 'none', inGracePeriod: false),
      );
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildScreen({
  required CheckoutNotifier Function() checkoutFactory,
  String planId = 'woleh_paid_monthly',
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) =>
            CheckoutWebViewScreen(planId: planId),
      ),
      GoRoute(
        path: '/plans',
        builder: (_, __) => const Scaffold(body: Text('Plans')),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('Home')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      checkoutNotifierProvider.overrideWith(checkoutFactory),
      meNotifierProvider.overrideWith(_FreeMeNotifier.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CheckoutWebViewScreen', () {
    group('loading state', () {
      testWidgets('shows a progress indicator while loading', (tester) async {
        await tester.pumpWidget(
          _buildScreen(checkoutFactory: _LoadingCheckoutNotifier.new),
        );
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('shows AppBar title "Complete payment"', (tester) async {
        await tester.pumpWidget(
          _buildScreen(checkoutFactory: _LoadingCheckoutNotifier.new),
        );
        await tester.pump();

        expect(find.text('Complete payment'), findsOneWidget);
      });

      testWidgets('close button navigates to /plans', (tester) async {
        await tester.pumpWidget(
          _buildScreen(checkoutFactory: _LoadingCheckoutNotifier.new),
        );
        await tester.pump();

        await tester.tap(find.byTooltip('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Plans'), findsOneWidget);
      });
    });

    group('error state', () {
      testWidgets('shows "Payment not completed" heading', (tester) async {
        await tester.pumpWidget(
          _buildScreen(checkoutFactory: _FailedCheckoutNotifier.new),
        );
        await tester.pump();

        expect(find.text('Payment not completed'), findsOneWidget);
      });

      testWidgets('shows error message from state', (tester) async {
        await tester.pumpWidget(
          _buildScreen(checkoutFactory: _FailedCheckoutNotifier.new),
        );
        await tester.pump();

        expect(
          find.text('Something went wrong. Please try again.'),
          findsOneWidget,
        );
      });

      testWidgets('shows Retry and "Back to plans" buttons', (tester) async {
        await tester.pumpWidget(
          _buildScreen(checkoutFactory: _FailedCheckoutNotifier.new),
        );
        await tester.pump();

        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Back to plans'), findsOneWidget);
      });

      testWidgets('"Back to plans" navigates to /plans', (tester) async {
        await tester.pumpWidget(
          _buildScreen(checkoutFactory: _FailedCheckoutNotifier.new),
        );
        await tester.pump();

        await tester.tap(find.text('Back to plans'));
        await tester.pumpAndSettle();

        expect(find.text('Plans'), findsOneWidget);
      });
    });
  });
}
