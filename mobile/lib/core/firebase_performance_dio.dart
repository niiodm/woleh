import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_performance/firebase_performance.dart';

import 'firebase_monitoring.dart';

const _kMetricExtraKey = 'firebase_perf_http_metric';

/// Records each HTTP call for Firebase Performance (latency, status code).
///
/// No-ops when Firebase is not initialized or monitoring is disabled.
class FirebasePerformanceInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!kFirebaseMonitoringEnabled || Firebase.apps.isEmpty) {
      handler.next(options);
      return;
    }
    HttpMetric? metric;
    try {
      metric = FirebasePerformance.instance.newHttpMetric(
        options.uri.toString(),
        _httpMethod(options.method),
      );
    } catch (_) {
      handler.next(options);
      return;
    }
    options.extra[_kMetricExtraKey] = metric;
    unawaited(metric.start().then((_) => handler.next(options)).catchError((_) {
      handler.next(options);
    }));
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    unawaited(_finish(response.requestOptions, response.statusCode));
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    unawaited(_finish(err.requestOptions, err.response?.statusCode));
    handler.next(err);
  }

  Future<void> _finish(RequestOptions options, int? statusCode) async {
    final metric = options.extra[_kMetricExtraKey] as HttpMetric?;
    if (metric == null) return;
    if (statusCode != null) {
      metric.httpResponseCode = statusCode;
    }
    try {
      await metric.stop();
    } catch (_) {}
  }

  static HttpMethod _httpMethod(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return HttpMethod.Get;
      case 'POST':
        return HttpMethod.Post;
      case 'PUT':
        return HttpMethod.Put;
      case 'PATCH':
        return HttpMethod.Patch;
      case 'DELETE':
        return HttpMethod.Delete;
      case 'HEAD':
        return HttpMethod.Head;
      case 'OPTIONS':
        return HttpMethod.Options;
      default:
        return HttpMethod.Get;
    }
  }
}
