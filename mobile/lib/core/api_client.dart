import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app_error.dart';
import 'auth_state.dart';

part 'api_client.g.dart';

/// Base URL injected at build time via `--dart-define=API_BASE_URL=...`.
/// Falls back to the Android emulator loopback when not specified.
const _kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

@Riverpod(keepAlive: true)
ApiClient apiClient(Ref ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: '$_kApiBaseUrl/api/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors
    ..add(_AuthInterceptor(ref))
    ..add(_ErrorInterceptor());

  return ApiClient(dio);
}

class ApiClient {
  const ApiClient(this.dio);

  final Dio dio;
}

/// Attaches `Authorization: Bearer <token>` when a token is present.
class _AuthInterceptor extends Interceptor {
  const _AuthInterceptor(this._ref);

  final Ref _ref;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _ref.read(authStateProvider).valueOrNull;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

/// Maps HTTP status codes to typed [AppError] subclasses so callers can
/// pattern-match without inspecting raw [DioException] objects.
class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    final serverMsg = _extractMessage(err.response);

    final appError = switch (status) {
      null => NetworkError(),
      401 => UnauthorizedError(serverMsg ?? 'Session expired'),
      403 => ForbiddenError(serverMsg ?? 'Access denied'),
      429 => RateLimitedError(serverMsg ?? 'Too many requests, please wait'),
      final s when s >= 500 => ServerError(serverMsg ?? 'Server error'),
      _ => UnknownError(serverMsg ?? 'Unexpected error ($status)'),
    };

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        error: appError,
        response: err.response,
        type: err.type,
      ),
    );
  }

  String? _extractMessage(Response<dynamic>? response) {
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      return data['message'] as String?;
    }
    return null;
  }
}
