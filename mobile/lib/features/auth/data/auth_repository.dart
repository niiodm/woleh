import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api_client.dart';
import 'auth_dto.dart';

part 'auth_repository.g.dart';

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) =>
    AuthRepository(ref.watch(apiClientProvider).dio);

class AuthRepository {
  const AuthRepository(this._dio);

  final Dio _dio;

  Future<SendOtpResponse> sendOtp(String phoneE164) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/send-otp',
      data: {'phoneE164': phoneE164},
    );
    final data = (response.data!['data'] as Map<String, dynamic>);
    return SendOtpResponse.fromJson(data);
  }

  Future<VerifyOtpResponse> verifyOtp({
    required String phoneE164,
    required String otp,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/verify-otp',
      data: {'phoneE164': phoneE164, 'otp': otp},
    );
    final data = (response.data!['data'] as Map<String, dynamic>);
    return VerifyOtpResponse.fromJson(data);
  }

  /// Exchanges a refresh token for a new access + refresh token pair (FR-A2).
  Future<RefreshResponse> refresh(String refreshToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    return RefreshResponse.fromJson(
        response.data!['data'] as Map<String, dynamic>);
  }

  /// Revokes all refresh tokens for the token's owner (FR-A2).
  /// Clears stored tokens from secure storage regardless of server response.
  Future<void> logout({String? refreshToken}) async {
    await _dio.post<void>(
      '/auth/logout',
      data: {'refreshToken': refreshToken},
    );
  }
}
