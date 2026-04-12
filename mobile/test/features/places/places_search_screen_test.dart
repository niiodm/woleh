import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/places/data/place_list_repository.dart';
import 'package:odm_clarity_woleh_mobile/features/places/presentation/places_search_screen.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _RecordingPlaceListRepository extends PlaceListRepository {
  _RecordingPlaceListRepository(super.dio, super.prefs);

  final List<List<String>> watchPuts = [];
  final List<List<String>> broadcastPuts = [];

  @override
  Future<PlaceListSnapshot> getWatchList() async =>
      const PlaceListSnapshot(names: []);

  @override
  Future<PlaceListSnapshot> getBroadcastList() async =>
      const PlaceListSnapshot(names: []);

  @override
  Future<List<String>> putWatchList(List<String> names) async {
    watchPuts.add(List<String>.from(names));
    return names;
  }

  @override
  Future<List<String>> putBroadcastList(List<String> names) async {
    broadcastPuts.add(List<String>.from(names));
    return names;
  }
}

class _MeWatchAndBroadcast extends MeNotifier {
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

class _MeWatchOnly extends MeNotifier {
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

class _MeBroadcastOnly extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
        me: const MeResponse(
          profile: MeProfile(userId: '1', phoneE164: '+233241234567'),
          permissions: [
            'woleh.account.profile',
            'woleh.plans.read',
            'woleh.place.broadcast',
          ],
          tier: 'paid',
          limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 50),
          subscription: MeSubscription(
            status: 'active',
            currentPeriodEnd: '2026-05-09T00:00:00Z',
            inGracePeriod: false,
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _harness({
  required Widget child,
  required List<Override> overrides,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('Show me buses is disabled when list is empty', (tester) async {
    await tester.pumpWidget(
      _harness(
        child: const PlacesSearchScreen(),
        overrides: [
          meNotifierProvider.overrideWith(_MeWatchAndBroadcast.new),
          placeListRepositoryProvider.overrideWith(
            (_) => _RecordingPlaceListRepository(Dio(), prefs),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final buses = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Show me buses'),
    );
    expect(buses.onPressed, isNull);
  });

  testWidgets(
      'Show me buses saves watch list then clears broadcast when allowed',
      (tester) async {
    final repo = _RecordingPlaceListRepository(Dio(), prefs);
    await tester.pumpWidget(
      _harness(
        child: const PlacesSearchScreen(),
        overrides: [
          meNotifierProvider.overrideWith(_MeWatchAndBroadcast.new),
          placeListRepositoryProvider.overrideWith((_) => repo),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Accra Central');
    await tester.tap(find.byTooltip('Add to list'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show me buses'));
    await tester.pumpAndSettle();

    expect(repo.watchPuts, [
      ['Accra Central'],
    ]);
    expect(repo.broadcastPuts, [
      <String>[],
    ]);
  });

  testWidgets(
      'Show me buses does not clear broadcast without broadcast permission',
      (tester) async {
    final repo = _RecordingPlaceListRepository(Dio(), prefs);
    await tester.pumpWidget(
      _harness(
        child: const PlacesSearchScreen(),
        overrides: [
          meNotifierProvider.overrideWith(_MeWatchOnly.new),
          placeListRepositoryProvider.overrideWith((_) => repo),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Tema');
    await tester.tap(find.byTooltip('Add to list'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show me buses'));
    await tester.pumpAndSettle();

    expect(repo.watchPuts, [
      ['Tema'],
    ]);
    expect(repo.broadcastPuts, isEmpty);
  });

  testWidgets(
      'Show me passengers saves broadcast then clears watch when allowed',
      (tester) async {
    final repo = _RecordingPlaceListRepository(Dio(), prefs);
    await tester.pumpWidget(
      _harness(
        child: const PlacesSearchScreen(),
        overrides: [
          meNotifierProvider.overrideWith(_MeWatchAndBroadcast.new),
          placeListRepositoryProvider.overrideWith((_) => repo),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Stop A');
    await tester.tap(find.byTooltip('Add to list'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show me passengers'));
    await tester.pumpAndSettle();

    expect(repo.broadcastPuts, [
      ['Stop A'],
    ]);
    expect(repo.watchPuts, [
      <String>[],
    ]);
  });

  testWidgets(
      'Show me passengers does not clear watch without watch permission',
      (tester) async {
    final repo = _RecordingPlaceListRepository(Dio(), prefs);
    await tester.pumpWidget(
      _harness(
        child: const PlacesSearchScreen(),
        overrides: [
          meNotifierProvider.overrideWith(_MeBroadcastOnly.new),
          placeListRepositoryProvider.overrideWith((_) => repo),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Stop B');
    await tester.tap(find.byTooltip('Add to list'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show me passengers'));
    await tester.pumpAndSettle();

    expect(repo.broadcastPuts, [
      ['Stop B'],
    ]);
    expect(repo.watchPuts, isEmpty);
  });

  testWidgets('missing watch permission routes to plans for Show me buses',
      (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const PlacesSearchScreen(),
        ),
        GoRoute(
          path: '/plans',
          builder: (_, __) => const Scaffold(body: Text('PlansScreen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meNotifierProvider.overrideWith(_MeBroadcastOnly.new),
          placeListRepositoryProvider.overrideWith(
            (_) => _RecordingPlaceListRepository(Dio(), prefs),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'X');
    await tester.tap(find.byTooltip('Add to list'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show me buses'));
    await tester.pumpAndSettle();

    expect(find.text('PlansScreen'), findsOneWidget);
  });

  testWidgets('pops after successful save when opened on a stack',
      (tester) async {
    final repo = _RecordingPlaceListRepository(Dio(), prefs);
    late final GoRouter router;
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.push('/places/search'),
                child: const Text('Open search'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/places/search',
          builder: (_, __) => const PlacesSearchScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meNotifierProvider.overrideWith(_MeWatchOnly.new),
          placeListRepositoryProvider.overrideWith((_) => repo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Kumasi');
    await tester.tap(find.byTooltip('Add to list'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show me buses'));
    await tester.pumpAndSettle();

    expect(find.text('Open search'), findsOneWidget);
    expect(repo.watchPuts, [
      ['Kumasi'],
    ]);
  });
}
