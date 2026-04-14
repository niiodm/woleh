import 'package:dio/dio.dart';

import '../../../core/app_error.dart';

/// User-facing copy for saved-list API failures (offline, network, etc.).
String savedListUserMessage(Object? error) {
  if (error == null) {
    return 'Something went wrong. Please try again.';
  }
  if (error is OfflineError) {
    return '${error.message} Try again when you are back online.';
  }
  if (error is NetworkError) {
    return error.message;
  }
  if (error is AppError) {
    return error.message;
  }
  if (error is DioException) {
    final inner = error.error;
    if (inner is AppError) return inner.message;
    return 'Could not reach the server. Check your connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}
