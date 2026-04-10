import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import '../../../core/app_error.dart';
import '../../../core/offline_dio.dart';
import '../../../core/shared_preferences_provider.dart';
import 'place_names_dto.dart';

part 'place_list_repository.g.dart';

@Riverpod(keepAlive: true)
PlaceListRepository placeListRepository(Ref ref) => PlaceListRepository(
      ref.watch(apiClientProvider).dio,
      ref.watch(sharedPreferencesProvider),
    );

/// Result of loading a place list from the network or offline cache.
class PlaceListSnapshot {
  const PlaceListSnapshot({required this.names, this.fromCache = false});

  final List<String> names;
  final bool fromCache;
}

/// Data-layer access for the place-list endpoints (API_CONTRACT.md §6.7–§6.10).
///
/// Throws a typed [AppError] subclass on failure (mapped from HTTP status and
/// server error code by [AppErrorInterceptor]):
/// - [PlaceValidationError] — 400 `VALIDATION_ERROR` (empty / too-long / duplicate name)
/// - [PlaceLimitError]      — 403 `OVER_LIMIT` (user's list cap exceeded)
/// - [ForbiddenError]       — 403 `PERMISSION_DENIED` (missing `woleh.place.watch` /
///                            `woleh.place.broadcast`)
/// - [UnauthorizedError]    — 401 (token missing or expired)
class PlaceListRepository {
  const PlaceListRepository(this._dio, this._prefs);

  final Dio _dio;
  final SharedPreferences _prefs;

  static const _watchPath = '/me/places/watch';
  static const _broadcastPath = '/me/places/broadcast';
  static const _watchCacheKey = 'cache.places.watch';
  static const _broadcastCacheKey = 'cache.places.broadcast';

  // ── watch list ─────────────────────────────────────────────────────────────

  /// Returns the display-form names from the caller's watch list,
  /// or an empty list if no list has been saved yet.
  Future<PlaceListSnapshot> getWatchList() =>
      _getList(_watchPath, _watchCacheKey);

  /// Replaces the caller's watch list with [names].
  ///
  /// The server deduplicates by normalized form (first occurrence kept) and
  /// enforces the tier limit. Returns the saved display-form list.
  Future<List<String>> putWatchList(List<String> names) =>
      _putList(_watchPath, _watchCacheKey, names);

  // ── broadcast list ─────────────────────────────────────────────────────────

  /// Returns the ordered display-form names from the caller's broadcast list,
  /// or an empty list if no list has been saved yet.
  Future<PlaceListSnapshot> getBroadcastList() =>
      _getList(_broadcastPath, _broadcastCacheKey);

  /// Replaces the caller's broadcast list with [names] (order is preserved).
  ///
  /// The server rejects duplicates after normalization with a 400 error.
  /// Returns the saved display-form list.
  Future<List<String>> putBroadcastList(List<String> names) =>
      _putList(_broadcastPath, _broadcastCacheKey, names);

  // ── private helpers ────────────────────────────────────────────────────────

  Future<PlaceListSnapshot> _getList(String path, String cacheKey) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(path);
      final names = _parseEnvelope(response.data!);
      await _writeListCache(cacheKey, names);
      return PlaceListSnapshot(names: names, fromCache: false);
    } on DioException catch (e) {
      if (isOfflineDioException(e)) {
        final cached = _readListCache(cacheKey);
        if (cached != null) {
          return PlaceListSnapshot(names: cached, fromCache: true);
        }
        throw const OfflineError();
      }
      rethrow;
    }
  }

  Future<List<String>> _putList(
    String path,
    String cacheKey,
    List<String> names,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      path,
      data: PlaceNamesDto(names: names).toJson(),
    );
    final saved = _parseEnvelope(response.data!);
    await _writeListCache(cacheKey, saved);
    return saved;
  }

  static List<String> _parseEnvelope(Map<String, dynamic> envelope) {
    final data = envelope['data'] as Map<String, dynamic>;
    return PlaceNamesDto.fromJson(data).names;
  }

  Future<void> _writeListCache(String cacheKey, List<String> names) async {
    await _prefs.setString(
      cacheKey,
      jsonEncode(PlaceNamesDto(names: names).toJson()),
    );
  }

  List<String>? _readListCache(String cacheKey) {
    final raw = _prefs.getString(cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return PlaceNamesDto.fromJson(map).names;
    } on FormatException {
      return null;
    }
  }
}
