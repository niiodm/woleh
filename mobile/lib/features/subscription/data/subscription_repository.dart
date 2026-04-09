import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api_client.dart';
import 'checkout_dto.dart';

part 'subscription_repository.g.dart';

@Riverpod(keepAlive: true)
SubscriptionRepository subscriptionRepository(Ref ref) =>
    SubscriptionRepository(ref.watch(apiClientProvider).dio);

/// Data-layer access for `/api/v1/subscription/checkout`.
class SubscriptionRepository {
  const SubscriptionRepository(this._dio);

  final Dio _dio;

  Future<CheckoutResponse> startCheckout(String planId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/subscription/checkout',
      data: {'planId': planId},
    );
    return CheckoutResponse.fromJson(
      response.data!['data'] as Map<String, dynamic>,
    );
  }
}
