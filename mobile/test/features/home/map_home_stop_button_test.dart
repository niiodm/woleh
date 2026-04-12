import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:odm_clarity_woleh_mobile/core/auth_state.dart';
import 'package:odm_clarity_woleh_mobile/core/location_onboarding.dart';
import 'package:odm_clarity_woleh_mobile/core/shared_preferences_provider.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/places/data/place_list_repository.dart';
import 'package:odm_clarity_woleh_mobile/features/places/presentation/broadcast_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/places/presentation/watch_notifier.dart';
import 'package:odm_clarity_woleh_mobile/main.dart';

import '../../support/pump_map_home.dart';

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

class _AuthToken extends AuthState {
  @override
  Future<String?> build() async => 'test-token';
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

class _WatchNonEmpty extends WatchNotifier {
  @override
  WatchState build() => const WatchReady(names: ['Kumasi']);
}

class _BroadcastEmpty extends BroadcastNotifier {
  @override
  BroadcastState build() => const BroadcastReady(names: []);
}

class _WatchEmpty extends WatchNotifier {
  @override
  WatchState build() => const WatchReady(names: []);
}

class _BroadcastNonEmpty extends BroadcastNotifier {
  @override
  BroadcastState build() => const BroadcastReady(names: ['Stop A', 'Stop B']);
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      kLocationOnboardingCompletedKey: true,
    });
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('Stop watching issues PUT watch with empty list', (tester) async {
    final repo = _RecordingPlaceListRepository(Dio(), prefs);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStateProvider.overrideWith(_AuthToken.new),
          meNotifierProvider.overrideWith(_MeWatchAndBroadcast.new),
          watchNotifierProvider.overrideWith(_WatchNonEmpty.new),
          broadcastNotifierProvider.overrideWith(_BroadcastEmpty.new),
          placeListRepositoryProvider.overrideWith((_) => repo),
        ],
        child: const WolehApp(),
      ),
    );
    await pumpWolehWithMap(tester);

    expect(find.byTooltip('Stop watching'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop watching'));
    await tester.pumpAndSettle();

    expect(repo.watchPuts, [
      <String>[],
    ]);
    expect(repo.broadcastPuts, isEmpty);
  });

  testWidgets('Stop broadcasting issues PUT broadcast with empty list',
      (tester) async {
    final repo = _RecordingPlaceListRepository(Dio(), prefs);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStateProvider.overrideWith(_AuthToken.new),
          meNotifierProvider.overrideWith(_MeWatchAndBroadcast.new),
          watchNotifierProvider.overrideWith(_WatchEmpty.new),
          broadcastNotifierProvider.overrideWith(_BroadcastNonEmpty.new),
          placeListRepositoryProvider.overrideWith((_) => repo),
        ],
        child: const WolehApp(),
      ),
    );
    await pumpWolehWithMap(tester);

    expect(find.byTooltip('Stop broadcasting'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop broadcasting'));
    await tester.pumpAndSettle();

    expect(repo.broadcastPuts, [
      <String>[],
    ]);
    expect(repo.watchPuts, isEmpty);
  });

  testWidgets('Broadcast list wins when both lists are non-empty (stop tap)',
      (tester) async {
    final repo = _RecordingPlaceListRepository(Dio(), prefs);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStateProvider.overrideWith(_AuthToken.new),
          meNotifierProvider.overrideWith(_MeWatchAndBroadcast.new),
          watchNotifierProvider.overrideWith(_WatchNonEmpty.new),
          broadcastNotifierProvider.overrideWith(_BroadcastNonEmpty.new),
          placeListRepositoryProvider.overrideWith((_) => repo),
        ],
        child: const WolehApp(),
      ),
    );
    await pumpWolehWithMap(tester);

    expect(find.byTooltip('Stop broadcasting'), findsOneWidget);
    expect(find.byTooltip('Stop watching'), findsNothing);

    await tester.tap(find.byTooltip('Stop broadcasting'));
    await tester.pumpAndSettle();

    expect(repo.broadcastPuts, [
      <String>[],
    ]);
    expect(repo.watchPuts, isEmpty);
  });
}
