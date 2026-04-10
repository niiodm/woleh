import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:odm_clarity_woleh_mobile/core/location/location_fix.dart';
import 'package:odm_clarity_woleh_mobile/shared/location_map.dart';
import 'package:odm_clarity_woleh_mobile/shared/map_location_pin.dart';

void main() {
  testWidgets('LocationMap builds with self and peers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationMap(
            self: const LocationFix(latitude: 5.6, longitude: -0.19),
            peers: const [
              MapLocationPin(id: '2', latitude: 5.61, longitude: -0.18),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(LocationMap), findsOneWidget);
  });

  testWidgets('LocationMap builds empty (fallback center)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LocationMap(self: null, peers: []),
        ),
      ),
    );

    expect(find.byType(LocationMap), findsOneWidget);
  });
}
