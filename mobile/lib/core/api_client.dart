import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app_error.dart';
import 'auth_state.dart';
import 'auth_token_storage.dart';

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
  final storage = ref.read(authTokenStorageProvider);
  final authNotifier = ref.read(authStateProvider.notifier);

  // Separate bare Dio used only for the refresh endpoint so that refresh calls
  // do not recurse through TokenRefreshInterceptor.
  final refreshDio = Dio(
    BaseOptions(
      baseUrl: '$_kApiBaseUrl/api/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  final dio = Dio(
    BaseOptions(
      baseUrl: '$_kApiBaseUrl/api/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  final tokenRefreshInterceptor = TokenRefreshInterceptor(
    getRefreshToken: storage.readRefreshToken,
    storeTokens: (accessToken, refreshToken) async {
      // setTokens updates in-memory state (so _AuthInterceptor picks it up on
      // retry) and writes both tokens to secure storage.
      await authNotifier.setTokens(accessToken, refreshToken);
    },
    signOut: authNotifier.signOut,
    refreshTokens: (rawRefreshToken) async {
      final resp = await refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': rawRefreshToken},
      );
      final data = resp.data!['data'] as Map<String, dynamic>;
      return (data['accessToken'] as String, data['refreshToken'] as String);
    },
    retry: dio.fetch,
  );

  dio.interceptors.addAll([
    _AuthInterceptor(ref),
    if (kDebugMode)
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (msg) => debugPrint('[API] $msg'),
      ),
    AppErrorInterceptor(),
    // TokenRefreshInterceptor is last so it runs first on errors (interceptors
    // are called in reverse-add order for onError).
    tokenRefreshInterceptor,
  ]);

  return ApiClient(dio);
}

class ApiClient {
  const ApiClient(this.dio);

  final Dio dio;
}

/// Intercepts 401 responses, attempts a silent token refresh, and retries the
/// original request. On refresh failure, clears stored tokens and triggers
/// sign-out.
///
/// Add this interceptor **last** so it runs **first** during error handling
/// (Dio calls error interceptors in reverse-add order).
///
/// The [retry] callback is [Dio.fetch] on the parent Dio. It is injected so
/// tests can supply a mock without a real network call.
class TokenRefreshInterceptor extends Interceptor {
  TokenRefreshInterceptor({
    required Future<String?> Function() getRefreshToken,
    required Future<void> Function(String accessToken, String refreshToken)
        storeTokens,
    required Future<void> Function() signOut,
    required Future<(String, String)> Function(String rawRefreshToken)
        refreshTokens,
    required Future<Response<dynamic>> Function(RequestOptions) retry,
  })  : _getRefreshToken = getRefreshToken,
        _storeTokens = storeTokens,
        _signOut = signOut,
        _refreshTokens = refreshTokens,
        _retry = retry;

  final Future<String?> Function() _getRefreshToken;
  final Future<void> Function(String, String) _storeTokens;
  final Future<void> Function() _signOut;
  final Future<(String, String)> Function(String) _refreshTokens;
  final Future<Response<dynamic>> Function(RequestOptions) _retry;

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    final refreshToken = await _getRefreshToken();
    if (refreshToken == null) {
      return handler.next(err);
    }

    try {
      final (newAccessToken, newRefreshToken) =
          await _refreshTokens(refreshToken);
      // Update in-memory auth state so _AuthInterceptor attaches the new token
      // on the retry, and persist both tokens to secure storage.
      await _storeTokens(newAccessToken, newRefreshToken);
      final retryResponse = await _retry(err.requestOptions);
      handler.resolve(retryResponse);
    } catch (_) {
      await _signOut();
      handler.next(err);
    }
  }
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

    // Use next() (not reject()) so subsequent interceptors — e.g.
    // TokenRefreshInterceptor — can still see and act on this error.
    handler.next(
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
