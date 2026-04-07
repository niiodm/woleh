import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:odm_clarity_woleh_mobile/main.dart';

void main() {
  testWidgets('shows phase label from Riverpod', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: MyHomePage(title: 'Woleh')),
      ),
    );

    expect(find.text('Phase 0'), findsOneWidget);
  });
}
