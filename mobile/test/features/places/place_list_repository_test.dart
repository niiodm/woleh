import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:odm_clarity_woleh_mobile/core/api_client.dart';
import 'package:odm_clarity_woleh_mobile/core/app_error.dart';
import 'package:odm_clarity_woleh_mobile/features/places/data/place_list_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Mock Dio adapter ─────────────────────────────────────────────────────────

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Dio _buildDio({required int statusCode, required Map<String, dynamic> body}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api/v1'));
  // Add the real error interceptor so error-mapping tests exercise the full
  // production code path.
  dio.interceptors.add(AppErrorInterceptor());
  dio.httpClientAdapter =
      _MockAdapter(statusCode: statusCode, body: jsonEncode(body));
  return dio;
}

Future<PlaceListRepository> _repo(
  int statusCode,
  Map<String, dynamic> body,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return PlaceListRepository(
    _buildDio(statusCode: statusCode, body: body),
    prefs,
  );
}

Map<String, dynamic> _okEnvelope(List<String> names) => {
      'result': 'OK',
      'message': 'OK',
      'data': {'names': names},
    };

Map<String, dynamic> _errEnvelope(String code, String message) => {
      'result': 'ERROR',
      'code': code,
      'message': message,
    };

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── getWatchList ────────────────────────────────────────────────────────────

  group('getWatchList', () {
    test('200 — returns parsed names', () async {
      final repo = await _repo(200, _okEnvelope(['Madina', 'Lapaz']));
      final snap = await repo.getWatchList();
      expect(snap.names, ['Madina', 'Lapaz']);
      expect(snap.fromCache, isFalse);
    });

    test('200 — empty list returns empty', () async {
      final repo = await _repo(200, _okEnvelope([]));
      final snap = await repo.getWatchList();
      expect(snap.names, isEmpty);
    });

    test('401 — throws UnauthorizedError', () async {
      final repo = await _repo(
          401, _errEnvelope('UNAUTHORIZED', 'Session expired'));
      expect(
        () => repo.getWatchList(),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'error', isA<UnauthorizedError>())),
      );
    });

    test('403 PERMISSION_DENIED — throws ForbiddenError', () async {
      final repo = await _repo(
          403, _errEnvelope('PERMISSION_DENIED', 'Permission required'));
      expect(
        () => repo.getWatchList(),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'error', isA<ForbiddenError>())),
      );
    });
  });

  // ── putWatchList ────────────────────────────────────────────────────────────

  group('putWatchList', () {
    test('200 — returns saved list (server may dedupe)', () async {
      // Server dedupes "circle " → "Circle" is kept; returns deduped list.
      final repo = await _repo(200, _okEnvelope(['Circle']));
      expect(await repo.putWatchList(['Circle', 'circle ']), ['Circle']);
    });

    test('400 VALIDATION_ERROR — throws PlaceValidationError', () async {
      final repo = await _repo(
          400, _errEnvelope('VALIDATION_ERROR', 'Place name must not be empty'));
      expect(
        () => repo.putWatchList(['  ']),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'error', isA<PlaceValidationError>())),
      );
    });

    test('403 OVER_LIMIT — throws PlaceLimitError', () async {
      final repo = await _repo(
          403, _errEnvelope('OVER_LIMIT', 'Exceeded watch list limit of 5'));
      expect(
        () => repo.putWatchList(['A', 'B', 'C', 'D', 'E', 'F']),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'error', isA<PlaceLimitError>())),
      );
    });
  });

  // ── getBroadcastList ────────────────────────────────────────────────────────

  group('getBroadcastList', () {
    test('200 — returns ordered names', () async {
      final repo = await _repo(200, _okEnvelope(['Kaneshie', 'Madina', 'Circle']));
      final snap = await repo.getBroadcastList();
      expect(snap.names, ['Kaneshie', 'Madina', 'Circle']);
    });

    test('403 PERMISSION_DENIED — throws ForbiddenError', () async {
      final repo = await _repo(
          403, _errEnvelope('PERMISSION_DENIED', 'Permission required: woleh.place.broadcast'));
      expect(
        () => repo.getBroadcastList(),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'error', isA<ForbiddenError>())),
      );
    });
  });

  // ── putBroadcastList ────────────────────────────────────────────────────────

  group('putBroadcastList', () {
    test('200 — returns saved list preserving order', () async {
      final repo = await _repo(200, _okEnvelope(['Circle', 'Madina', 'Lapaz']));
      expect(
        await repo.putBroadcastList(['Circle', 'Madina', 'Lapaz']),
        ['Circle', 'Madina', 'Lapaz'],
      );
    });

    test('400 VALIDATION_ERROR for duplicate normalized name — throws PlaceValidationError',
        () async {
      final repo = await _repo(
          400,
          _errEnvelope('VALIDATION_ERROR',
              'Duplicate place name in broadcast list (after normalization): "madina "'));
      expect(
        () => repo.putBroadcastList(['Madina', 'madina ']),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'error', isA<PlaceValidationError>())),
      );
    });
  });
}
