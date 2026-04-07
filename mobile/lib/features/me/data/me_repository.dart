import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api_client.dart';
import 'me_dto.dart';

part 'me_repository.g.dart';

@Riverpod(keepAlive: true)
MeRepository meRepository(Ref ref) =>
    MeRepository(ref.watch(apiClientProvider).dio);

/// Data-layer access for `/api/v1/me` endpoints.
class MeRepository {
  const MeRepository(this._dio);

  final Dio _dio;

  Future<MeResponse> getMe() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    return MeResponse.fromJson(
      response.data!['data'] as Map<String, dynamic>,
    );
  }

  Future<void> patchDisplayName(String displayName) async {
    await _dio.patch<void>(
      '/me/profile',
      data: {'displayName': displayName},
    );
  }
}
