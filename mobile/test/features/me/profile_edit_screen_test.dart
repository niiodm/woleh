import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_repository.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/profile_edit_screen.dart';

class _FakeMeRepo extends MeRepository {
  _FakeMeRepo(super.dio, super.prefs);

  int patchCalls = 0;

  @override
  Future<void> patchDisplayName(String displayName) async {
    patchCalls++;
  }
}

class _MeForEdit extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
        me: MeResponse(
          profile: const MeProfile(
            userId: '1',
            phoneE164: '+233241234567',
            displayName: 'Old Name',
          ),
          permissions: const [
            'woleh.account.profile',
            'woleh.plans.read',
            'woleh.place.watch',
          ],
          tier: 'free',
          limits: const MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
          subscription: MeSubscription(status: 'none', inGracePeriod: false),
        ),
      );

  @override
  Future<void> refresh() async {}
}

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('successful save pops back when opened via push', (tester) async {
    final repo = _FakeMeRepo(Dio(), prefs);
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (context, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.push('/me/edit'),
                child: const Text('Open edit'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/me/edit',
          builder: (_, __) => const ProfileEditScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meNotifierProvider.overrideWith(_MeForEdit.new),
          meRepositoryProvider.overrideWith((_) => repo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit profile'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'New Name');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Open edit'), findsOneWidget);
    expect(repo.patchCalls, 1);
  });

  testWidgets('successful save goes to profile when stack cannot pop',
      (tester) async {
    final repo = _FakeMeRepo(Dio(), prefs);
    final router = GoRouter(
      initialLocation: '/me/edit',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (_, __) =>
              const Scaffold(body: Text('Profile fallback')),
        ),
        GoRoute(
          path: '/me/edit',
          builder: (_, __) => const ProfileEditScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meNotifierProvider.overrideWith(_MeForEdit.new),
          meRepositoryProvider.overrideWith((_) => repo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit profile'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Solo');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Profile fallback'), findsOneWidget);
    expect(repo.patchCalls, 1);
  });
}
