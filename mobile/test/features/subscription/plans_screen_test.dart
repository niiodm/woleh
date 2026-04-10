import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/subscription/data/plans_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/subscription/presentation/plans_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/subscription/presentation/plans_screen.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _freePlan = PlanDto(
  planId: 'woleh_free',
  displayName: 'Woleh Free',
  permissionsGranted: [
    'woleh.account.profile',
    'woleh.plans.read',
    'woleh.place.watch',
  ],
  limits: PlanLimits(placeWatchMax: 5, placeBroadcastMax: 0),
  price: PlanPrice(amountMinor: 0, currency: 'GHS'),
);

const _paidPlan = PlanDto(
  planId: 'woleh_paid_monthly',
  displayName: 'Woleh Pro',
  permissionsGranted: [
    'woleh.account.profile',
    'woleh.plans.read',
    'woleh.place.watch',
    'woleh.place.broadcast',
  ],
  limits: PlanLimits(placeWatchMax: 50, placeBroadcastMax: 50),
  price: PlanPrice(amountMinor: 999, currency: 'GHS'),
);

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

class _StubPlansNotifier extends PlansNotifier {
  @override
  Future<List<PlanDto>> build() async => [_freePlan, _paidPlan];
}

class _StubPlansNotifierError extends PlansNotifier {
  @override
  Future<List<PlanDto>> build() async =>
      throw Exception('Failed to load plans');
}

class _FreeMeNotifier extends MeNotifier {
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

class _PaidMeNotifier extends MeNotifier {
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
// Helper
// ---------------------------------------------------------------------------

Widget _buildScreen({
  required PlansNotifier Function() plansFactory,
  required MeNotifier Function() meFactory,
}) {
  // GoRouter is required because PlansScreen uses context.canPop() and
  // context.push() from the go_router extensions.
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const PlansScreen(),
      ),
      GoRoute(
        path: '/checkout/:planId',
        builder: (_, __) => const Scaffold(body: Text('Checkout')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      plansNotifierProvider.overrideWith(plansFactory),
      meNotifierProvider.overrideWith(meFactory),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PlansScreen', () {
    group('card layout', () {
      testWidgets('shows both plan cards', (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            plansFactory: _StubPlansNotifier.new,
            meFactory: _FreeMeNotifier.new,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Woleh Free'), findsOneWidget);
        expect(find.text('Woleh Pro'), findsOneWidget);
      });

      testWidgets('renders all four permission labels on the paid card',
          (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            plansFactory: _StubPlansNotifier.new,
            meFactory: _FreeMeNotifier.new,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Manage profile'), findsWidgets);
        expect(find.text('View plans'), findsWidgets);
        expect(find.text('Watch places'), findsWidgets);
        expect(find.text('Broadcast your route'), findsOneWidget);
      });

      testWidgets('shows limits text on paid card', (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            plansFactory: _StubPlansNotifier.new,
            meFactory: _FreeMeNotifier.new,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Broadcast up to 50'), findsOneWidget);
        expect(find.text('No broadcasting'), findsOneWidget);
      });
    });

    group('price formatting', () {
      testWidgets('shows "Free" for the free plan', (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            plansFactory: _StubPlansNotifier.new,
            meFactory: _FreeMeNotifier.new,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Free'), findsOneWidget);
      });

      testWidgets('formats paid plan price as GHS X.XX / month', (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            plansFactory: _StubPlansNotifier.new,
            meFactory: _FreeMeNotifier.new,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('GHS 9.99 / month'), findsOneWidget);
      });
    });

    group('current-plan highlight', () {
      testWidgets('free user: free plan shows "Current plan", paid shows "Subscribe"',
          (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            plansFactory: _StubPlansNotifier.new,
            meFactory: _FreeMeNotifier.new,
          ),
        );
        await tester.pumpAndSettle();

        // "Current plan" chip + disabled button on free card.
        expect(find.text('Current plan'), findsWidgets);
        // Subscribe button on paid card.
        expect(find.text('Subscribe'), findsOneWidget);
      });

      testWidgets('paid user: paid plan shows "Current plan", free shows disabled',
          (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            plansFactory: _StubPlansNotifier.new,
            meFactory: _PaidMeNotifier.new,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Current plan'), findsWidgets);
        // No active Subscribe button for paid user.
        expect(find.text('Subscribe'), findsNothing);
      });
    });

    group('Subscribe CTA', () {
      testWidgets('Subscribe button is enabled for free-tier user on paid plan',
          (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            plansFactory: _StubPlansNotifier.new,
            meFactory: _FreeMeNotifier.new,
          ),
        );
        await tester.pumpAndSettle();

        final subscribeBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Subscribe'),
        );
        expect(subscribeBtn.onPressed, isNotNull);
      });
    });

    group('error state', () {
      testWidgets('shows error view with retry button on load failure',
          (tester) async {
        await tester.pumpWidget(
          _buildScreen(
            plansFactory: _StubPlansNotifierError.new,
            meFactory: _FreeMeNotifier.new,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Could not load plans'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      });
    });
  });
}
