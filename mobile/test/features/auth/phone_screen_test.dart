import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:odm_clarity_woleh_mobile/features/auth/presentation/phone_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/auth/presentation/phone_screen.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Wraps [PhoneScreen] in a minimal GoRouter so `context.go(...)` calls
/// in the screen don't throw during widget tests.
Widget _buildPhoneScreen({List<Override> overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/auth/phone',
    routes: [
      GoRoute(
        path: '/auth/phone',
        builder: (_, __) => const PhoneScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        builder: (_, __) => const Scaffold(body: Text('OTP screen')),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

class _LoadingPhoneNotifier extends PhoneNotifier {
  @override
  PhoneState build() => const PhoneState(status: PhoneSendStatus.loading);
}

class _RateLimitedPhoneNotifier extends PhoneNotifier {
  @override
  PhoneState build() => const PhoneState(
        status: PhoneSendStatus.error,
        errorMessage: 'Too many requests, please wait',
      );
}

class _ServerErrorPhoneNotifier extends PhoneNotifier {
  @override
  PhoneState build() => const PhoneState(
        status: PhoneSendStatus.error,
        errorMessage: 'Server error',
      );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PhoneScreen', () {
    group('idle state', () {
      testWidgets('renders phone text field', (tester) async {
        await tester.pumpWidget(_buildPhoneScreen());
        await tester.pumpAndSettle();

        expect(find.byType(TextFormField), findsOneWidget);
      });

      testWidgets('renders Send code button', (tester) async {
        await tester.pumpWidget(_buildPhoneScreen());
        await tester.pumpAndSettle();

        expect(find.text('Send code'), findsOneWidget);
      });

      testWidgets('no error banner visible initially', (tester) async {
        await tester.pumpWidget(_buildPhoneScreen());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.error_outline), findsNothing);
      });
    });

    group('loading state', () {
      // Use pump() rather than pumpAndSettle(): CircularProgressIndicator has
      // an infinite animation that never settles.
      testWidgets('shows circular progress indicator', (tester) async {
        await tester.pumpWidget(_buildPhoneScreen(
          overrides: [
            phoneNotifierProvider.overrideWith(_LoadingPhoneNotifier.new),
          ],
        ));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('Send code button is disabled', (tester) async {
        await tester.pumpWidget(_buildPhoneScreen(
          overrides: [
            phoneNotifierProvider.overrideWith(_LoadingPhoneNotifier.new),
          ],
        ));
        await tester.pump();

        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
      });
    });

    group('error state', () {
      testWidgets('shows error banner with 429 message', (tester) async {
        await tester.pumpWidget(_buildPhoneScreen(
          overrides: [
            phoneNotifierProvider
                .overrideWith(_RateLimitedPhoneNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.text('Too many requests, please wait'), findsOneWidget);
      });

      testWidgets('shows error banner with server error message', (tester) async {
        await tester.pumpWidget(_buildPhoneScreen(
          overrides: [
            phoneNotifierProvider.overrideWith(_ServerErrorPhoneNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.text('Server error'), findsOneWidget);
      });
    });

    group('form validation', () {
      testWidgets('empty submit shows validation error', (tester) async {
        await tester.pumpWidget(_buildPhoneScreen());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Send code'));
        await tester.pumpAndSettle();

        expect(find.text('Enter a phone number'), findsOneWidget);
      });

      testWidgets('invalid phone shows validation error', (tester) async {
        await tester.pumpWidget(_buildPhoneScreen());
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField), 'abc');
        await tester.tap(find.text('Send code'));
        await tester.pumpAndSettle();

        expect(find.textContaining('valid phone number'), findsOneWidget);
      });
    });
  });
}
