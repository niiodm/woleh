import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:odm_clarity_woleh_mobile/core/auth_state.dart';
import 'package:odm_clarity_woleh_mobile/core/location/location_fix.dart';
import 'package:odm_clarity_woleh_mobile/core/location/location_source.dart';
import 'package:odm_clarity_woleh_mobile/core/location/location_source_provider.dart';
import 'package:odm_clarity_woleh_mobile/core/shared_preferences_provider.dart';
import 'package:odm_clarity_woleh_mobile/features/location/presentation/location_publish_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_repository.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _AuthWithToken extends AuthState {
  @override
  Future<String?> build() async => 'test-access-token';
}

class _MeSharingOn extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
        me: MeResponse(
          profile: const MeProfile(
            userId: '1',
            phoneE164: '+2331',
            locationSharingEnabled: true,
          ),
          permissions: const [
            'woleh.place.watch',
            'woleh.place.broadcast',
          ],
          tier: 'paid',
          limits: const MeLimits(placeWatchMax: 50, placeBroadcastMax: 50),
          subscription: MeSubscription(
            status: 'active',
            currentPeriodEnd: '2026-05-01T00:00:00Z',
            inGracePeriod: false,
          ),
        ),
      );
}

class _MeSharingOff extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
        me: MeResponse(
          profile: const MeProfile(
            userId: '1',
            phoneE164: '+2331',
            locationSharingEnabled: false,
          ),
          permissions: const [
            'woleh.place.watch',
            'woleh.place.broadcast',
          ],
          tier: 'paid',
          limits: const MeLimits(placeWatchMax: 50, placeBroadcastMax: 50),
          subscription: MeSubscription(
            status: 'active',
            currentPeriodEnd: '2026-05-01T00:00:00Z',
            inGracePeriod: false,
          ),
        ),
      );
}

class _MeNoLocationPerm extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
        me: const MeResponse(
          profile: MeProfile(
            userId: '1',
            phoneE164: '+2331',
            locationSharingEnabled: true,
          ),
          permissions: ['woleh.account.profile'],
          tier: 'free',
          limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
          subscription: MeSubscription(status: 'none', inGracePeriod: false),
        ),
      );
}

class _FakeLocationSource implements LocationSource {
  _FakeLocationSource(this._fixes);

  final Stream<LocationFix> _fixes;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationAuthorization> checkAuthorization() async =>
      LocationAuthorization.whileInUse;

  @override
  Future<LocationAuthorization> requestWhenInUse() async =>
      LocationAuthorization.whileInUse;

  @override
  Stream<LocationFix> watchPosition({
    LocationAccuracyTier accuracy = LocationAccuracyTier.high,
    double distanceFilterMeters = 0,
  }) =>
      _fixes;

  @override
  Future<LocationFix> getCurrentPosition({
    LocationAccuracyTier accuracy = LocationAccuracyTier.high,
  }) async =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('locationPublishLifecycleAllowsStream', () {
    test('allows resumed and inactive', () {
      expect(locationPublishLifecycleAllowsStream(AppLifecycleState.resumed), isTrue);
      expect(locationPublishLifecycleAllowsStream(AppLifecycleState.inactive), isTrue);
      expect(locationPublishLifecycleAllowsStream(null), isTrue);
    });

    test('disallows paused, hidden, detached', () {
      expect(locationPublishLifecycleAllowsStream(AppLifecycleState.paused), isFalse);
      expect(locationPublishLifecycleAllowsStream(AppLifecycleState.detached), isFalse);
      expect(locationPublishLifecycleAllowsStream(AppLifecycleState.hidden), isFalse);
    });
  });

  group('LocationPublishNotifier', () {
    late SharedPreferences prefs;
    late List<Map<String, dynamic>> posts;
    late Dio dio;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      posts = [];
      dio = Dio(
        BaseOptions(
          baseUrl: 'http://localhost/api/v1',
          validateStatus: (_) => true,
        ),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (req, handler) {
            if (req.path.contains('location')) {
              posts.add(Map<String, dynamic>.from(req.data as Map));
            }
            handler.resolve(
              Response(
                requestOptions: req,
                statusCode: 200,
                data: {'data': null},
              ),
            );
          },
        ),
      );
    });

    test('POST /me/location when sharing on and fix arrives', () async {
      final fixes = StreamController<LocationFix>.broadcast();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStateProvider.overrideWith(_AuthWithToken.new),
          meNotifierProvider.overrideWith(_MeSharingOn.new),
          meRepositoryProvider.overrideWith(
            (ref) => MeRepository(dio, ref.watch(sharedPreferencesProvider)),
          ),
          locationSourceProvider.overrideWithValue(_FakeLocationSource(fixes.stream)),
        ],
      );
      addTearDown(container.dispose);

      container.read(locationPublishNotifierProvider);
      await pumpEventQueue();

      fixes.add(const LocationFix(latitude: 5.0, longitude: -0.1));
      await pumpEventQueue();

      expect(posts, hasLength(1));
      expect(posts.single['latitude'], 5.0);
      expect(posts.single['longitude'], -0.1);

      await fixes.close();
    });

    test('throttles to about one post per second', () async {
      final fixes = StreamController<LocationFix>.broadcast();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStateProvider.overrideWith(_AuthWithToken.new),
          meNotifierProvider.overrideWith(_MeSharingOn.new),
          meRepositoryProvider.overrideWith(
            (ref) => MeRepository(dio, ref.watch(sharedPreferencesProvider)),
          ),
          locationSourceProvider.overrideWithValue(_FakeLocationSource(fixes.stream)),
        ],
      );
      addTearDown(container.dispose);

      container.read(locationPublishNotifierProvider);
      await pumpEventQueue();

      fixes.add(const LocationFix(latitude: 5.0, longitude: -0.1));
      await pumpEventQueue();
      fixes.add(const LocationFix(latitude: 6.0, longitude: -0.2));
      await pumpEventQueue();
      expect(posts, hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      fixes.add(const LocationFix(latitude: 7.0, longitude: -0.3));
      await pumpEventQueue();

      expect(posts, hasLength(2));
      expect(posts.last['latitude'], 7.0);

      await fixes.close();
    });

    test('does not subscribe when sharing is off', () async {
      final fixes = StreamController<LocationFix>.broadcast();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStateProvider.overrideWith(_AuthWithToken.new),
          meNotifierProvider.overrideWith(_MeSharingOff.new),
          meRepositoryProvider.overrideWith(
            (ref) => MeRepository(dio, ref.watch(sharedPreferencesProvider)),
          ),
          locationSourceProvider.overrideWithValue(_FakeLocationSource(fixes.stream)),
        ],
      );
      addTearDown(container.dispose);

      container.read(locationPublishNotifierProvider);
      await pumpEventQueue();

      fixes.add(const LocationFix(latitude: 5.0, longitude: -0.1));
      await pumpEventQueue();

      expect(posts, isEmpty);
      await fixes.close();
    });

    test('does not subscribe without watch or broadcast permission', () async {
      final fixes = StreamController<LocationFix>.broadcast();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStateProvider.overrideWith(_AuthWithToken.new),
          meNotifierProvider.overrideWith(_MeNoLocationPerm.new),
          meRepositoryProvider.overrideWith(
            (ref) => MeRepository(dio, ref.watch(sharedPreferencesProvider)),
          ),
          locationSourceProvider.overrideWithValue(_FakeLocationSource(fixes.stream)),
        ],
      );
      addTearDown(container.dispose);

      container.read(locationPublishNotifierProvider);
      await pumpEventQueue();

      fixes.add(const LocationFix(latitude: 5.0, longitude: -0.1));
      await pumpEventQueue();

      expect(posts, isEmpty);
      await fixes.close();
    });
  });
}
