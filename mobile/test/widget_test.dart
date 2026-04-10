import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:odm_clarity_woleh_mobile/core/auth_state.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';
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

  testWidgets('authenticated user sees home screen with profile', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(_AuthenticatedState.new),
          meNotifierProvider.overrideWith(_StubMeNotifier.new),
        ],
        child: const WolehApp(),
      ),
    );
    await tester.pumpAndSettle();

    // AppBar title
    expect(find.text('Woleh'), findsOneWidget);
    // Profile name rendered
    expect(find.text('Ama'), findsOneWidget);
    // Phone shown
    expect(find.text('+233241234567'), findsOneWidget);
    // Permissions visible
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
  });
}

// ---------------------------------------------------------------------------
// Stub notifiers
// ---------------------------------------------------------------------------

class _UnauthenticatedState extends AuthState {
  @override
  Future<String?> build() async => null;
}

class _AuthenticatedState extends AuthState {
  @override
  Future<String?> build() async => 'fake-token';
}

class _StubMeNotifier extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
        me: const MeResponse(
          profile: MeProfile(
            userId: '1',
            phoneE164: '+233241234567',
            displayName: 'Ama',
          ),
          permissions: [
            'woleh.account.profile',
            'woleh.plans.read',
            'woleh.place.watch',
          ],
          tier: 'free',
          limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
          subscription: MeSubscription(
            status: 'none',
            inGracePeriod: false,
          ),
        ),
      );
}
