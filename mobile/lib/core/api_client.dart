import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app_error.dart';
import 'auth_state.dart';

part 'api_client.g.dart';

// Base URL injected at build time via --dart-define=API_BASE_URL=...
//
// Defaults to the Android emulator's loopback alias for the host machine.
// Physical devices on the same Wi-Fi network need the host's actual LAN IP:
//
//   flutter run --dart-define=API_BASE_URL=http://<your-lan-ip>:8080
//
// Find your LAN IP on macOS:  ipconfig getifaddr en0
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

  dio.interceptors.add(_AuthInterceptor(ref));

  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (msg) => debugPrint('[API] $msg'),
      ),
    );
  }

  dio.interceptors.add(AppErrorInterceptor());

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

/// Maps HTTP status codes (and server error codes) to typed [AppError]
/// subclasses so callers can pattern-match without inspecting raw
/// [DioException] objects.
///
/// Exposed publicly so tests can add it to a mock [Dio] instance and verify
/// that responses are mapped to the correct [AppError] type.
class AppErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    final serverMsg = _extractMessage(err.response);
    final serverCode = _extractCode(err.response);

    final appError = switch (status) {
      null => NetworkError(),
      401 => UnauthorizedError(serverMsg ?? 'Session expired'),
      // 400 VALIDATION_ERROR covers: empty name, over-limit code points,
      // duplicate normalised name in broadcast list.
      400 when serverCode == 'VALIDATION_ERROR' =>
        PlaceValidationError(serverMsg ?? 'Invalid place name'),
      // 403 OVER_LIMIT: user has the permission but exceeded their list cap.
      403 when serverCode == 'OVER_LIMIT' =>
        PlaceLimitError(serverMsg ?? 'Place list limit exceeded'),
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

  String? _extractCode(Response<dynamic>? response) {
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      return data['code'] as String?;
    }
    return null;
  }
}
