import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:odm_clarity_woleh_mobile/core/auth_state.dart';
import 'package:odm_clarity_woleh_mobile/main.dart';

void main() {
  testWidgets('unauthenticated user sees phone/sign-in screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(_UnauthenticatedState.new),
        ],
        child: const WolehApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('authenticated user is redirected to home screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(_AuthenticatedState.new),
        ],
        child: const WolehApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
  });
}

/// Stub notifier that always resolves to null (no token).
class _UnauthenticatedState extends AuthState {
  @override
  Future<String?> build() async => null;
}

/// Stub notifier that always resolves to a token (authenticated).
class _AuthenticatedState extends AuthState {
  @override
  Future<String?> build() async => 'fake-token';
}
