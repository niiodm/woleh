import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:odm_clarity_woleh_mobile/core/api_client.dart';
import 'package:odm_clarity_woleh_mobile/core/app_error.dart';

// ── Mock HTTP adapter ─────────────────────────────────────────────────────────

/// Returns a fixed response for every request.
class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        jsonEncode(body),
        statusCode,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      );

  @override
  void close({bool force = false}) {}
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Map<String, dynamic> _okEnvelope(Map<String, dynamic> data) => {
      'result': 'SUCCESS',
      'message': 'ok',
      'data': data,
    };

Map<String, dynamic> _errorEnvelope(String code) => {
      'result': 'ERROR',
      'code': code,
      'message': code,
    };

/// Builds a Dio instance with [AppErrorInterceptor] then [interceptor] so that
/// on error: [interceptor] runs first, then [AppErrorInterceptor].
Dio _buildDio({
  required TokenRefreshInterceptor interceptor,
  required int statusCode,
  required Map<String, dynamic> body,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api/v1'));
  dio.interceptors.add(AppErrorInterceptor());
  dio.interceptors.add(interceptor);
  dio.httpClientAdapter = _FixedAdapter(statusCode: statusCode, body: body);
  return dio;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('TokenRefreshInterceptor', () {
    test(
        '401 with stored refresh token → refresh succeeds → '
        'retry response returned', () async {
      String? storedAccessToken;
      String? storedRefreshToken;

      final retryData = {'names': <String>[]};

      final interceptor = TokenRefreshInterceptor(
        getRefreshToken: () async => 'stored-refresh-token',
        storeTokens: (access, refresh) async {
          storedAccessToken = access;
          storedRefreshToken = refresh;
        },
        signOut: () async => fail('signOut should not be called'),
        refreshTokens: (_) async =>
            ('new-access-token', 'new-refresh-token'),
        retry: (options) async => Response(
          requestOptions: options,
          statusCode: 200,
          data: _okEnvelope(retryData),
        ),
      );

      final dio = _buildDio(
        interceptor: interceptor,
        statusCode: 401,
        body: _errorEnvelope('UNAUTHORIZED'),
      );

      final response = await dio.get<Map<String, dynamic>>('/me');

      expect(response.statusCode, 200);
      expect(storedAccessToken, 'new-access-token');
      expect(storedRefreshToken, 'new-refresh-token');
    });

    test('401 with no stored refresh token → UnauthorizedError propagates',
        () async {
      final interceptor = TokenRefreshInterceptor(
        getRefreshToken: () async => null,
        storeTokens: (_, __) async => fail('storeTokens should not be called'),
        signOut: () async => fail('signOut should not be called'),
        refreshTokens: (_) async => fail('refreshTokens should not be called'),
        retry: (_) async => fail('retry should not be called'),
      );

      final dio = _buildDio(
        interceptor: interceptor,
        statusCode: 401,
        body: _errorEnvelope('UNAUTHORIZED'),
      );

      await expectLater(
        dio.get<Map<String, dynamic>>('/me'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<UnauthorizedError>(),
          ),
        ),
      );
    });

    test(
        '401 with stored refresh token → refresh fails → '
        'signOut called → UnauthorizedError propagates', () async {
      var signOutCalled = false;

      final interceptor = TokenRefreshInterceptor(
        getRefreshToken: () async => 'stored-refresh-token',
        storeTokens: (_, __) async => fail('storeTokens should not be called'),
        signOut: () async {
          signOutCalled = true;
        },
        refreshTokens: (_) async =>
            throw DioException(
              requestOptions: RequestOptions(path: '/auth/refresh'),
              response: Response(
                requestOptions: RequestOptions(path: '/auth/refresh'),
                statusCode: 401,
                data: _errorEnvelope('INVALID_REFRESH_TOKEN'),
              ),
              type: DioExceptionType.badResponse,
            ),
        retry: (_) async => fail('retry should not be called'),
      );

      final dio = _buildDio(
        interceptor: interceptor,
        statusCode: 401,
        body: _errorEnvelope('UNAUTHORIZED'),
      );

      await expectLater(
        dio.get<Map<String, dynamic>>('/me'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<UnauthorizedError>(),
          ),
        ),
      );

      expect(signOutCalled, isTrue);
    });

    test('non-401 errors pass through without touching refresh logic',
        () async {
      final interceptor = TokenRefreshInterceptor(
        getRefreshToken: () async => fail('getRefreshToken should not be called'),
        storeTokens: (_, __) async => fail('storeTokens should not be called'),
        signOut: () async => fail('signOut should not be called'),
        refreshTokens: (_) async => fail('refreshTokens should not be called'),
        retry: (_) async => fail('retry should not be called'),
      );

      final dio = _buildDio(
        interceptor: interceptor,
        statusCode: 403,
        body: _errorEnvelope('FORBIDDEN'),
      );

      await expectLater(
        dio.get<Map<String, dynamic>>('/me'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<ForbiddenError>(),
          ),
        ),
      );
    });
  });
}
