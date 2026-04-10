import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:odm_clarity_woleh_mobile/core/ws_client.dart';
import 'package:odm_clarity_woleh_mobile/shared/ws_status_banner.dart';

void main() {
  group('WsStatusBannerCore', () {
    testWidgets('reconnecting shows reconnecting copy', (tester) async {
      final listenable =
          ValueNotifier<WsConnectionState>(WsConnectionState.reconnecting);
      addTearDown(listenable.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WsStatusBannerCore(
              listenable: listenable,
              onRetry: () {},
            ),
          ),
        ),
      );

      expect(
        find.text('Live updates unavailable — reconnecting…'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('connected hides status copy', (tester) async {
      final listenable =
          ValueNotifier<WsConnectionState>(WsConnectionState.connected);
      addTearDown(listenable.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WsStatusBannerCore(
              listenable: listenable,
              onRetry: () {},
            ),
          ),
        ),
      );

      expect(find.text('Live updates offline'), findsNothing);
      expect(
        find.text('Live updates unavailable — reconnecting…'),
        findsNothing,
      );
    });

    testWidgets('connecting hides status copy', (tester) async {
      final listenable =
          ValueNotifier<WsConnectionState>(WsConnectionState.connecting);
      addTearDown(listenable.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WsStatusBannerCore(
              listenable: listenable,
              onRetry: () {},
            ),
          ),
        ),
      );

      expect(find.text('Live updates offline'), findsNothing);
      expect(
        find.text('Live updates unavailable — reconnecting…'),
        findsNothing,
      );
    });

    testWidgets('disconnected shows offline copy and Retry', (tester) async {
      final listenable =
          ValueNotifier<WsConnectionState>(WsConnectionState.disconnected);
      addTearDown(listenable.dispose);
      var retries = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WsStatusBannerCore(
              listenable: listenable,
              onRetry: () => retries++,
            ),
          ),
        ),
      );

      expect(find.text('Live updates offline'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });
  });
}
