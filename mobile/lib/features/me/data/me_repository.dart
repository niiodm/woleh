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
    await patchProfile(displayName: displayName);
  }

  /// Partial update (`PATCH /me/profile`). Omits null fields.
  Future<void> patchProfile({
    String? displayName,
    bool? productAnalyticsConsent,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['displayName'] = displayName;
    if (productAnalyticsConsent != null) {
      body['productAnalyticsConsent'] = productAnalyticsConsent;
    }
    if (body.isEmpty) return;
    await _dio.patch<void>('/me/profile', data: body);
  }

  /// Opt in/out of publishing fixes to matched peers (`PUT /me/location-sharing`).
  Future<void> putLocationSharing({required bool enabled}) async {
    await _dio.put<void>(
      '/me/location-sharing',
      data: {'enabled': enabled},
    );
  }

  /// Publishes a device fix to matched peers ([`API_CONTRACT.md`](../../../../../docs/API_CONTRACT.md) §6.4.1).
  Future<void> postLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    double? heading,
    double? speed,
    DateTime? recordedAt,
  }) async {
    final body = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
    };
    if (accuracyMeters != null) body['accuracyMeters'] = accuracyMeters;
    if (heading != null) body['heading'] = heading;
    if (speed != null) body['speed'] = speed;
    if (recordedAt != null) {
      body['recordedAt'] = recordedAt.toUtc().toIso8601String();
    }
    await _dio.post<void>('/me/location', data: body);
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
