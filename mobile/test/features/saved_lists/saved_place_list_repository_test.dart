import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odm_clarity_woleh_mobile/core/api_client.dart';
import 'package:odm_clarity_woleh_mobile/features/saved_lists/data/saved_place_list_repository.dart';

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

Dio _dio(int code, Object body) {
  final d = Dio(BaseOptions(baseUrl: 'http://test.local/api/v1'));
  d.interceptors.add(AppErrorInterceptor());
  d.httpClientAdapter = _MockAdapter(
    statusCode: code,
    body: body is String ? body : jsonEncode(body),
  );
  return d;
}

void main() {
  group('SavedPlaceListRepository', () {
    test('listSummaries parses rows', () async {
      final repo = SavedPlaceListRepository(_dio(200, {
        'result': 'SUCCESS',
        'data': [
          {
            'id': 1,
            'title': 'Trip',
            'placeCount': 2,
            'shareToken': 'tok',
            'updatedAt': '2026-04-14T12:00:00Z',
          },
        ],
      }));

      final rows = await repo.listSummaries();
      expect(rows, hasLength(1));
      expect(rows.single.id, 1);
      expect(rows.single.shareToken, 'tok');
      expect(rows.single.placeCount, 2);
    });

    test('create returns detail', () async {
      final repo = SavedPlaceListRepository(_dio(200, {
        'result': 'SUCCESS',
        'data': {
          'id': 3,
          'title': 'T',
          'names': ['A'],
          'shareToken': 'abc',
          'createdAt': '2026-04-14T12:00:00Z',
          'updatedAt': '2026-04-14T12:00:00Z',
        },
      }));

      final d = await repo.create(title: 'T', names: ['A']);
      expect(d.id, 3);
      expect(d.names, ['A']);
    });
  });
}
