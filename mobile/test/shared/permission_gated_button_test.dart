import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:odm_clarity_woleh_mobile/shared/permission_gated_button.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [widget] in a [MaterialApp.router] so GoRouter-dependent navigation
/// (context.push) works inside the widget under test.
Widget _buildHarness({
  required PermissionGatedButton child,
  List<String> extraRoutes = const ['/plans', '/broadcast'],
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(body: child),
      ),
      for (final path in extraRoutes)
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text('route: $path')),
        ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PermissionGatedButton — locked state', () {
    testWidgets('shows padlock icon when permission is absent', (tester) async {
      await tester.pumpWidget(_buildHarness(
        child: PermissionGatedButton(
          icon: Icons.radio_outlined,
          label: 'Broadcast your route',
          hasPermission: false,
          onTap: () {},
          onLockedTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('shows lockedMessage text', (tester) async {
      await tester.pumpWidget(_buildHarness(
        child: PermissionGatedButton(
          icon: Icons.radio_outlined,
          label: 'Broadcast your route',
          hasPermission: false,
          onTap: () {},
          onLockedTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Upgrade to unlock'), findsOneWidget);
    });

    testWidgets('tapping locked state calls onLockedTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_buildHarness(
        child: PermissionGatedButton(
          icon: Icons.radio_outlined,
          label: 'Broadcast your route',
          hasPermission: false,
          onTap: () {},
          onLockedTap: () => tapped = true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Broadcast your route'));
      expect(tapped, isTrue);
    });

    testWidgets('does NOT call onTap when locked', (tester) async {
      var primaryTapped = false;
      await tester.pumpWidget(_buildHarness(
        child: PermissionGatedButton(
          icon: Icons.radio_outlined,
          label: 'Broadcast your route',
          hasPermission: false,
          onTap: () => primaryTapped = true,
          onLockedTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Broadcast your route'));
      expect(primaryTapped, isFalse);
    });
  });

  group('PermissionGatedButton — unlocked state', () {
    testWidgets('shows forward arrow when permission is present', (tester) async {
      await tester.pumpWidget(_buildHarness(
        child: PermissionGatedButton(
          icon: Icons.radio_outlined,
          label: 'Broadcast your route',
          hasPermission: true,
          onTap: () {},
          onLockedTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);
    });

    testWidgets('does NOT show padlock when permission is present', (tester) async {
      await tester.pumpWidget(_buildHarness(
        child: PermissionGatedButton(
          icon: Icons.radio_outlined,
          label: 'Broadcast your route',
          hasPermission: true,
          onTap: () {},
          onLockedTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock), findsNothing);
    });

    testWidgets('does NOT show lockedMessage when unlocked', (tester) async {
      await tester.pumpWidget(_buildHarness(
        child: PermissionGatedButton(
          icon: Icons.radio_outlined,
          label: 'Broadcast your route',
          hasPermission: true,
          onTap: () {},
          onLockedTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Upgrade to unlock'), findsNothing);
    });

    testWidgets('tapping unlocked state calls onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_buildHarness(
        child: PermissionGatedButton(
          icon: Icons.radio_outlined,
          label: 'Broadcast your route',
          hasPermission: true,
          onTap: () => tapped = true,
          onLockedTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Broadcast your route'));
      expect(tapped, isTrue);
    });

    testWidgets('tapping unlocked does NOT call onLockedTap', (tester) async {
      var lockedTapped = false;
      await tester.pumpWidget(_buildHarness(
        child: PermissionGatedButton(
          icon: Icons.radio_outlined,
          label: 'Broadcast your route',
          hasPermission: true,
          onTap: () {},
          onLockedTap: () => lockedTapped = true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Broadcast your route'));
      expect(lockedTapped, isFalse);
    });
  });

  group('PermissionGatedButton — custom lockedMessage', () {
    testWidgets('renders custom lockedMessage', (tester) async {
      await tester.pumpWidget(_buildHarness(
        child: PermissionGatedButton(
          icon: Icons.radio_outlined,
          label: 'Broadcast your route',
          hasPermission: false,
          lockedMessage: 'Subscribe to enable',
          onTap: () {},
          onLockedTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Subscribe to enable'), findsOneWidget);
      expect(find.text('Upgrade to unlock'), findsNothing);
    });
  });
}
