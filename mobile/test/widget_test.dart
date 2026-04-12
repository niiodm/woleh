import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_map_home.dart';

import 'package:odm_clarity_woleh_mobile/core/auth_state.dart';
import 'package:odm_clarity_woleh_mobile/core/shared_preferences_provider.dart';
import 'package:odm_clarity_woleh_mobile/core/telemetry_consent.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';
import 'package:odm_clarity_woleh_mobile/main.dart';

void main() {
  late SharedPreferences testPrefs;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      kTelemetryProductAnalyticsConsentKey: true,
    });
    testPrefs = await SharedPreferences.getInstance();
  });

  testWidgets('unauthenticated user sees phone/sign-in screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(testPrefs),
          authStateProvider.overrideWith(_UnauthenticatedState.new),
        ],
        child: const WolehApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('authenticated user sees map home; profile from icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(testPrefs),
          authStateProvider.overrideWith(_AuthenticatedState.new),
          meNotifierProvider.overrideWith(_StubMeNotifier.new),
        ],
        child: const WolehApp(),
      ),
    );
    await pumpWolehWithMap(tester);

    expect(find.text('Search places'), findsOneWidget);

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Profile'), findsOneWidget);
    expect(find.text('Ama'), findsOneWidget);
    expect(find.text('+233241234567'), findsOneWidget);
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
      subscription: MeSubscription(status: 'none', inGracePeriod: false),
    ),
  );
}
