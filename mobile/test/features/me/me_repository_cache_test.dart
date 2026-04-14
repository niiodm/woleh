import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odm_clarity_woleh_mobile/core/app_error.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _OkAdapter implements HttpClientAdapter {
  _OkAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final _sampleMeData = {
  'profile': {
    'userId': '1',
    'phoneE164': '+233241234567',
    'displayName': 'Ama',
    'productAnalyticsConsent': false,
  },
  'permissions': ['woleh.account.profile'],
  'tier': 'free',
  'limits': {'placeWatchMax': 5, 'placeBroadcastMax': 0},
  'subscription': {
    'status': 'none',
    'currentPeriodEnd': null,
    'inGracePeriod': false,
  },
};

void main() {
  group('MeRepository offline cache', () {
    test('connection error + cache hit returns snapshot from cache', () async {
      SharedPreferences.setMockInitialValues({
        'cache.profile': jsonEncode(_sampleMeData),
      });
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api/v1'));
      dio.httpClientAdapter = _OfflineAdapter();
      final repo = MeRepository(dio, prefs);

      final snap = await repo.getMe();
      expect(snap.fromCache, isTrue);
      expect(snap.me.profile.displayName, 'Ama');
      expect(snap.me.limits.savedPlaceListMax, 10);
    });

    test('connection error + no cache throws OfflineError', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api/v1'));
      dio.httpClientAdapter = _OfflineAdapter();
      final repo = MeRepository(dio, prefs);

      expect(() => repo.getMe(), throwsA(isA<OfflineError>()));
    });

    test('successful GET persists cache', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api/v1'));
      final envelope = {
        'result': 'OK',
        'data': _sampleMeData,
      };
      dio.httpClientAdapter = _OkAdapter(jsonEncode(envelope));
      final repo = MeRepository(dio, prefs);

      final snap = await repo.getMe();
      expect(snap.fromCache, isFalse);
      final raw = prefs.getString('cache.profile');
      expect(raw, isNotNull);
      final roundTrip = MeResponse.fromJson(
        jsonDecode(raw!) as Map<String, dynamic>,
      );
      expect(roundTrip.tier, 'free');
      expect(snap.me.profile.displayName, roundTrip.profile.displayName);
      expect(roundTrip.limits.savedPlaceListMax, 10);
    });
  });
}
