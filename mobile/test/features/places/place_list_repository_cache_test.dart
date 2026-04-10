import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odm_clarity_woleh_mobile/core/app_error.dart';
import 'package:odm_clarity_woleh_mobile/features/places/data/place_list_repository.dart';
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

void main() {
  group('PlaceListRepository offline cache', () {
    test('watch: connection error + cache returns cached names', () async {
      SharedPreferences.setMockInitialValues({
        'cache.places.watch': jsonEncode({'names': ['Madina', 'Lapaz']}),
      });
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api/v1'));
      dio.httpClientAdapter = _OfflineAdapter();
      final repo = PlaceListRepository(dio, prefs);

      final snap = await repo.getWatchList();
      expect(snap.fromCache, isTrue);
      expect(snap.names, ['Madina', 'Lapaz']);
    });

    test('watch: connection error + empty prefs throws OfflineError', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api/v1'));
      dio.httpClientAdapter = _OfflineAdapter();
      final repo = PlaceListRepository(dio, prefs);

      expect(() => repo.getWatchList(), throwsA(isA<OfflineError>()));
    });

    test('broadcast: connection error + cache returns cached names', () async {
      SharedPreferences.setMockInitialValues({
        'cache.places.broadcast': jsonEncode({'names': ['A', 'B']}),
      });
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api/v1'));
      dio.httpClientAdapter = _OfflineAdapter();
      final repo = PlaceListRepository(dio, prefs);

      final snap = await repo.getBroadcastList();
      expect(snap.fromCache, isTrue);
      expect(snap.names, ['A', 'B']);
    });

    test('unknown error without response + cache still serves watch list',
        () async {
      SharedPreferences.setMockInitialValues({
        'cache.places.watch': jsonEncode({'names': ['Solo']}),
      });
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api/v1'));
      dio.httpClientAdapter = _ThrowingAdapter(
        DioException(
          requestOptions: RequestOptions(path: '/me/places/watch'),
          type: DioExceptionType.unknown,
        ),
      );
      final repo = PlaceListRepository(dio, prefs);

      final snap = await repo.getWatchList();
      expect(snap.fromCache, isTrue);
      expect(snap.names, ['Solo']);
    });
  });
}

class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.error);

  final DioException error;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw error;
  }

  @override
  void close({bool force = false}) {}
}
