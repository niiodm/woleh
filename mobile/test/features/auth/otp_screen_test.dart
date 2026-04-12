import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:odm_clarity_woleh_mobile/features/auth/presentation/otp_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/auth/presentation/otp_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _phone = '+233241234567';
const _expires = 300;

Widget _buildOtpScreen({List<Override> overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/auth/otp',
    routes: [
      GoRoute(
        path: '/auth/otp',
               builder: (_, __) => const OtpScreen(
              phone: _phone,
              expiresInSeconds: _expires,
              productAnalyticsConsent: true,
            ),
      ),
      GoRoute(
        path: '/auth/phone',
        builder: (_, __) => const Scaffold(body: Text('Phone screen')),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/auth/setup-name',
        builder: (_, __) => const Scaffold(body: Text('Setup name')),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Stub notifiers (family: keyed by phoneE164)
//
// All stubs override startCountdown as a no-op so the screen's initState
// callback does not create a periodic Timer that outlives the test.
// ---------------------------------------------------------------------------

class _IdleOtpNotifier extends OtpNotifier {
  @override
  OtpState build(String phoneE164) => const OtpState();
  @override
  void startCountdown(int seconds) {}
}

class _CountdownOtpNotifier extends OtpNotifier {
  @override
  OtpState build(String phoneE164) => const OtpState(countdownSeconds: 120);
  @override
  void startCountdown(int seconds) {}
}

class _CountdownExpiredOtpNotifier extends OtpNotifier {
  @override
  OtpState build(String phoneE164) => const OtpState(countdownSeconds: 0);
  @override
  void startCountdown(int seconds) {}
}

class _VerifyingOtpNotifier extends OtpNotifier {
  @override
  OtpState build(String phoneE164) =>
      const OtpState(status: OtpActionStatus.verifying);
  @override
  void startCountdown(int seconds) {}
}

class _ErrorOtpNotifier extends OtpNotifier {
  @override
  OtpState build(String phoneE164) => const OtpState(
        status: OtpActionStatus.error,
        errorMessage: 'Invalid OTP. Check the code and try again.',
      );
  @override
  void startCountdown(int seconds) {}
}

class _ResendingOtpNotifier extends OtpNotifier {
  @override
  OtpState build(String phoneE164) =>
      const OtpState(status: OtpActionStatus.resending);
  @override
  void startCountdown(int seconds) {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OtpScreen', () {
    group('layout', () {
      testWidgets('shows OTP text field', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone).overrideWith(_IdleOtpNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.byType(TextFormField), findsOneWidget);
      });

      testWidgets('shows Verify button', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone).overrideWith(_IdleOtpNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.text('Verify'), findsOneWidget);
      });

      testWidgets('shows phone number in subtitle', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone).overrideWith(_IdleOtpNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.textContaining(_phone), findsOneWidget);
      });
    });

    group('countdown active', () {
      testWidgets('shows remaining time label', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone).overrideWith(_CountdownOtpNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        // 120s = 2:00
        expect(find.textContaining('2:00'), findsOneWidget);
      });

      testWidgets('does not show Resend button while counting down',
          (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone).overrideWith(_CountdownOtpNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.text('Resend code'), findsNothing);
      });
    });

    group('countdown expired', () {
      testWidgets('shows Resend code button', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone)
                .overrideWith(_CountdownExpiredOtpNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.text('Resend code'), findsOneWidget);
      });

      testWidgets('does not show countdown label', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone)
                .overrideWith(_CountdownExpiredOtpNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.textContaining('Resend code in'), findsNothing);
      });
    });

    group('verifying state', () {
      // Use pump() rather than pumpAndSettle(): CircularProgressIndicator has
      // an infinite animation that never settles.
      testWidgets('shows progress indicator', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone).overrideWith(_VerifyingOtpNotifier.new),
          ],
        ));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsWidgets);
      });

      testWidgets('Verify button is disabled', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone).overrideWith(_VerifyingOtpNotifier.new),
          ],
        ));
        await tester.pump();

        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
      });
    });

    group('resending state', () {
      testWidgets('shows progress indicator in resend area', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone).overrideWith(_ResendingOtpNotifier.new),
          ],
        ));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsWidgets);
      });
    });

    group('error state', () {
      testWidgets('shows error banner with message', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone).overrideWith(_ErrorOtpNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(
          find.textContaining('Invalid OTP'),
          findsOneWidget,
        );
      });
    });

    group('form validation', () {
      testWidgets('empty submit shows validation error', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone).overrideWith(_IdleOtpNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Verify'));
        await tester.pumpAndSettle();

        expect(find.text('Verification code is required'), findsOneWidget);
      });

      testWidgets('fewer than 6 digits shows validation error', (tester) async {
        await tester.pumpWidget(_buildOtpScreen(
          overrides: [
            otpNotifierProvider(_phone).overrideWith(_IdleOtpNotifier.new),
          ],
        ));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField), '123');
        await tester.tap(find.text('Verify'));
        await tester.pumpAndSettle();

        expect(find.text('Verification code must be 6 digits'), findsOneWidget);
      });
    });
  });
}
