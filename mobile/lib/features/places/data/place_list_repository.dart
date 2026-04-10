import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api_client.dart';
import 'place_names_dto.dart';

part 'place_list_repository.g.dart';

@Riverpod(keepAlive: true)
PlaceListRepository placeListRepository(Ref ref) =>
    PlaceListRepository(ref.watch(apiClientProvider).dio);

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
  const PlaceListRepository(this._dio);

  final Dio _dio;

  static const _watchPath = '/me/places/watch';
  static const _broadcastPath = '/me/places/broadcast';

  // ── watch list ─────────────────────────────────────────────────────────────

  /// Returns the display-form names from the caller's watch list,
  /// or an empty list if no list has been saved yet.
  Future<List<String>> getWatchList() => _getList(_watchPath);

  /// Replaces the caller's watch list with [names].
  ///
  /// The server deduplicates by normalized form (first occurrence kept) and
  /// enforces the tier limit. Returns the saved display-form list.
  Future<List<String>> putWatchList(List<String> names) =>
      _putList(_watchPath, names);

  // ── broadcast list ─────────────────────────────────────────────────────────

  /// Returns the ordered display-form names from the caller's broadcast list,
  /// or an empty list if no list has been saved yet.
  Future<List<String>> getBroadcastList() => _getList(_broadcastPath);

  /// Replaces the caller's broadcast list with [names] (order is preserved).
  ///
  /// The server rejects duplicates after normalization with a 400 error.
  /// Returns the saved display-form list.
  Future<List<String>> putBroadcastList(List<String> names) =>
      _putList(_broadcastPath, names);

  // ── private helpers ────────────────────────────────────────────────────────

  Future<List<String>> _getList(String path) async {
    final response = await _dio.get<Map<String, dynamic>>(path);
    return _parseEnvelope(response.data!);
  }

  Future<List<String>> _putList(String path, List<String> names) async {
    final response = await _dio.put<Map<String, dynamic>>(
      path,
      data: PlaceNamesDto(names: names).toJson(),
    );
    return _parseEnvelope(response.data!);
  }

  static List<String> _parseEnvelope(Map<String, dynamic> envelope) {
    final data = envelope['data'] as Map<String, dynamic>;
    return PlaceNamesDto.fromJson(data).names;
  }
}
