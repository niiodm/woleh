import 'package:flutter_test/flutter_test.dart';

/// Map home embeds `flutter_map`, which schedules frames indefinitely, so
/// [WidgetTester.pumpAndSettle] never completes once the map is visible.
Future<void> pumpWolehWithMap(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}
