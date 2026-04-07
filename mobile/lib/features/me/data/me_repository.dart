import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api_client.dart';

part 'me_repository.g.dart';

@Riverpod(keepAlive: true)
MeRepository meRepository(Ref ref) =>
    MeRepository(ref.watch(apiClientProvider).dio);

/// Data-layer access for `/api/v1/me` endpoints.
///
/// Expanded in step 4.3 with `getMe()`; only `patchDisplayName` is needed
/// for the step-4.2 signup flow.
class MeRepository {
  const MeRepository(this._dio);

  final Dio _dio;

  Future<void> patchDisplayName(String displayName) async {
    await _dio.patch<void>(
      '/me/profile',
      data: {'displayName': displayName},
    );
  }
}
