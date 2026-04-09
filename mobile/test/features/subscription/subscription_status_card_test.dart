import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/subscription/presentation/subscription_status_card.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

MeResponse _paidMe({String currentPeriodEnd = '2026-05-09T00:00:00Z'}) =>
    MeResponse(
      profile: const MeProfile(userId: '1', phoneE164: '+233241234567'),
      permissions: const [
        'woleh.account.profile',
        'woleh.plans.read',
        'woleh.place.watch',
        'woleh.place.broadcast',
      ],
      tier: 'paid',
      limits: const MeLimits(placeWatchMax: 50, placeBroadcastMax: 50),
      subscription: MeSubscription(
        status: 'active',
        currentPeriodEnd: currentPeriodEnd,
        inGracePeriod: false,
      ),
    );

const _freeMe = MeResponse(
  profile: MeProfile(userId: '1', phoneE164: '+233241234567'),
  permissions: ['woleh.account.profile', 'woleh.plans.read', 'woleh.place.watch'],
  tier: 'free',
  limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
  subscription: MeSubscription(status: 'none', inGracePeriod: false),
);

/// Grace period: currentPeriodEnd 3 days ago → ~4 days remaining.
MeResponse _graceMe() {
  final threeAgo = DateTime.now().toUtc().subtract(const Duration(days: 3));
  return MeResponse(
    profile: const MeProfile(userId: '1', phoneE164: '+233241234567'),
    permissions: const ['woleh.account.profile', 'woleh.plans.read', 'woleh.place.watch'],
    tier: 'paid',
    limits: const MeLimits(placeWatchMax: 50, placeBroadcastMax: 50),
    subscription: MeSubscription(
      status: 'active',
      currentPeriodEnd: threeAgo.toIso8601String(),
      inGracePeriod: true,
    ),
  );
}

// ---------------------------------------------------------------------------
// Helper — wrap with GoRouter so context.push('/plans') is available
// ---------------------------------------------------------------------------

Widget _wrap(MeResponse me) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: Center(child: SubscriptionStatusCard(me: me)),
        ),
      ),
      GoRoute(
        path: '/plans',
        builder: (_, __) => const Scaffold(body: Text('Plans')),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SubscriptionStatusCard', () {
    group('paid / active state', () {
      testWidgets('shows "Renews" with formatted date', (tester) async {
        await tester.pumpWidget(_wrap(_paidMe()));
        await tester.pumpAndSettle();

        expect(find.textContaining('Renews'), findsOneWidget);
        expect(find.textContaining('9 May 2026'), findsOneWidget);
      });

      testWidgets('does not show upgrade link or warning banner', (tester) async {
        await tester.pumpWidget(_wrap(_paidMe()));
        await tester.pumpAndSettle();

        expect(find.textContaining('Upgrade'), findsNothing);
        expect(find.textContaining('expired'), findsNothing);
      });
    });

    group('free state', () {
      testWidgets('shows "Free plan · Upgrade →" text', (tester) async {
        await tester.pumpWidget(_wrap(_freeMe));
        await tester.pumpAndSettle();

        expect(find.textContaining('Free plan'), findsOneWidget);
        expect(find.textContaining('Upgrade'), findsOneWidget);
      });

      testWidgets('tapping Upgrade navigates to /plans', (tester) async {
        await tester.pumpWidget(_wrap(_freeMe));
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Upgrade'));
        await tester.pumpAndSettle();

        expect(find.text('Plans'), findsOneWidget);
      });

      testWidgets('does not show renews date or warning banner', (tester) async {
        await tester.pumpWidget(_wrap(_freeMe));
        await tester.pumpAndSettle();

        expect(find.textContaining('Renews'), findsNothing);
        expect(find.textContaining('expired'), findsNothing);
      });
    });

    group('grace period state', () {
      testWidgets('shows "Your subscription has expired" heading', (tester) async {
        await tester.pumpWidget(_wrap(_graceMe()));
        await tester.pumpAndSettle();

        expect(find.text('Your subscription has expired'), findsOneWidget);
      });

      testWidgets('shows days remaining message', (tester) async {
        await tester.pumpWidget(_wrap(_graceMe()));
        await tester.pumpAndSettle();

        // currentPeriodEnd is 3 days ago → 4 days remaining in 7-day grace period.
        expect(find.textContaining('days'), findsOneWidget);
      });

      testWidgets('"View plans" button navigates to /plans', (tester) async {
        await tester.pumpWidget(_wrap(_graceMe()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('View plans'));
        await tester.pumpAndSettle();

        expect(find.text('Plans'), findsOneWidget);
      });
    });
  });
}
