import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api_client.dart';
import 'plans_dto.dart';

part 'plans_repository.g.dart';

@Riverpod(keepAlive: true)
PlansRepository plansRepository(Ref ref) =>
    PlansRepository(ref.watch(apiClientProvider).dio);

/// Data-layer access for `/api/v1/subscription/plans`.
class PlansRepository {
  const PlansRepository(this._dio);

  final Dio _dio;

  Future<List<PlanDto>> getPlans() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/subscription/plans');
    final data = response.data!['data'] as List;
    return data
        .map((e) => PlanDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
