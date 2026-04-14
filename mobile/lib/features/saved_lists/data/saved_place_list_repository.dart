import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api_client.dart';
import '../../../core/api_config.dart';
import '../../../core/app_error.dart';
import 'saved_place_list_dto.dart';

part 'saved_place_list_repository.g.dart';

@Riverpod(keepAlive: true)
SavedPlaceListRepository savedPlaceListRepository(Ref ref) =>
    SavedPlaceListRepository(ref.watch(apiClientProvider).dio);

/// Authenticated CRUD for saved place lists plus unauthenticated public read by token.
class SavedPlaceListRepository {
  SavedPlaceListRepository(this._dio);

  final Dio _dio;

  static const _basePath = '/me/saved-place-lists';

  Future<List<SavedPlaceListSummaryDto>> listSummaries() async {
    final response = await _dio.get<Map<String, dynamic>>(_basePath);
    final list = response.data!['data'] as List<dynamic>;
    return list
        .map((e) =>
            SavedPlaceListSummaryDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SavedPlaceListDetailDto> create({
    String? title,
    required List<String> names,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      _basePath,
      data: {'title': title, 'names': names},
    );
    return SavedPlaceListDetailDto.fromJson(
      response.data!['data'] as Map<String, dynamic>,
    );
  }

  Future<SavedPlaceListDetailDto> getDetail(int id) async {
    final response = await _dio.get<Map<String, dynamic>>('$_basePath/$id');
    return SavedPlaceListDetailDto.fromJson(
      response.data!['data'] as Map<String, dynamic>,
    );
  }

  Future<SavedPlaceListDetailDto> replace({
    required int id,
    String? title,
    required List<String> names,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '$_basePath/$id',
      data: {'title': title, 'names': names},
    );
    return SavedPlaceListDetailDto.fromJson(
      response.data!['data'] as Map<String, dynamic>,
    );
  }

  Future<void> delete(int id) async {
    await _dio.delete<void>('$_basePath/$id');
  }

  /// No auth; uses a short-lived [Dio] so refresh / bearer are not applied.
  Future<SavedPlaceListPublicDto> getPublicByToken(String token) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    final path = '$apiHostBaseUrl/api/v1/public/saved-place-lists/$token';
    try {
      final response = await dio.get<Map<String, dynamic>>(path);
      final envelope = response.data!;
      final result = envelope['result'] as String?;
      if (result != 'SUCCESS') {
        throw UnknownError(envelope['message'] as String? ?? 'Unexpected response');
      }
      return SavedPlaceListPublicDto.fromJson(
        envelope['data'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const SavedListNotFoundError();
      }
      if (e.type == DioExceptionType.connectionError) {
        throw const NetworkError();
      }
      rethrow;
    }
  }
}
