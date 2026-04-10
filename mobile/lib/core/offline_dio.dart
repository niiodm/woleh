import 'package:dio/dio.dart';

/// True when the failure is likely due to no network reachability and there is
/// no HTTP response (per Phase 3 offline cache spec).
bool isOfflineDioException(DioException e) {
  if (e.response != null) return false;
  return e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.unknown;
}
