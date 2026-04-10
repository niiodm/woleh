import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/app_error.dart';
import '../../../core/offline_dio.dart';
import '../../../core/shared_preferences_provider.dart';
import 'me_dto.dart';

part 'me_repository.g.dart';

@Riverpod(keepAlive: true)
MeRepository meRepository(Ref ref) => MeRepository(
      ref.watch(apiClientProvider).dio,
      ref.watch(sharedPreferencesProvider),
    );

/// Data-layer access for `/api/v1/me` endpoints.
class MeRepository {
  const MeRepository(this._dio, this._prefs);

  final Dio _dio;
  final SharedPreferences _prefs;

  static const _cacheKey = 'cache.profile';

  Future<MeLoadSnapshot> getMe() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/me');
      final me = MeResponse.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
      await _prefs.setString(_cacheKey, jsonEncode(me.toJson()));
      return MeLoadSnapshot(me: me, fromCache: false);
    } on DioException catch (e) {
      if (isOfflineDioException(e)) {
        final cached = _readCachedMe();
        if (cached != null) {
          return MeLoadSnapshot(me: cached, fromCache: true);
        }
        throw const OfflineError();
      }
      rethrow;
    }
  }

  Future<void> patchDisplayName(String displayName) async {
    await _dio.patch<void>(
      '/me/profile',
      data: {'displayName': displayName},
    );
  }

  /// Registers or refreshes the FCM device token (Phase 3.4).
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    await _dio.post<void>(
      '/me/device-token',
      data: {'token': token, 'platform': platform},
    );
  }

  /// Removes the device token on sign-out.
  Future<void> deleteDeviceToken(String token) async {
    await _dio.delete<void>(
      '/me/device-token',
      data: {'token': token},
    );
  }

  MeResponse? _readCachedMe() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return MeResponse.fromJson(map);
    } on FormatException {
      return null;
    }
  }
}
