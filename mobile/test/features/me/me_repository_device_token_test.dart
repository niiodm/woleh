import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odm_clarity_woleh_mobile/features/me/data/me_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CaptureAdapter implements HttpClientAdapter {
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      '{"result":"SUCCESS","message":"OK","data":null}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('registerDeviceToken POSTs token and platform', () async {
    SharedPreferences.setMockInitialValues({});
    final adapter = _CaptureAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://x/api/v1'))
      ..httpClientAdapter = adapter;
    final repo = MeRepository(dio, await SharedPreferences.getInstance());

    await repo.registerDeviceToken(token: 'tok-1', platform: 'android');

    expect(adapter.last?.method, 'POST');
    expect(adapter.last?.path, '/me/device-token');
    expect(adapter.last?.data, {'token': 'tok-1', 'platform': 'android'});
  });

  test('deleteDeviceToken DELETEs with body', () async {
    SharedPreferences.setMockInitialValues({});
    final adapter = _CaptureAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://x/api/v1'))
      ..httpClientAdapter = adapter;
    final repo = MeRepository(dio, await SharedPreferences.getInstance());

    await repo.deleteDeviceToken('tok-2');

    expect(adapter.last?.method, 'DELETE');
    expect(adapter.last?.path, '/me/device-token');
    expect(adapter.last?.data, {'token': 'tok-2'});
  });
}
