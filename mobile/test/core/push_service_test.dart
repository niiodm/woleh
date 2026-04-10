import 'package:flutter_test/flutter_test.dart';
import 'package:odm_clarity_woleh_mobile/core/push_bootstrap.dart';

void main() {
  test('kPushEnabled is false without dart-define (CI / default builds)', () {
    expect(kPushEnabled, isFalse);
  });
}
