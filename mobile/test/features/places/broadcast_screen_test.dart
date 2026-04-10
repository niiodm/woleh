import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:odm_clarity_woleh_mobile/core/app_error.dart';
import 'package:odm_clarity_woleh_mobile/features/places/presentation/broadcast_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/places/presentation/broadcast_screen.dart';

// ---------------------------------------------------------------------------
// Stub notifier
// ---------------------------------------------------------------------------

class _StubBroadcastNotifier extends BroadcastNotifier {
  _StubBroadcastNotifier(this._initialState);

  final BroadcastState _initialState;

  @override
  BroadcastState build() => _initialState;
}

// ---------------------------------------------------------------------------
// Test helper
// ---------------------------------------------------------------------------

Widget _buildScreen(BroadcastState state) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const BroadcastScreen(),
      ),
      GoRoute(
        path: '/plans',
        builder: (_, __) => const Scaffold(body: Text('Plans')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      broadcastNotifierProvider
          .overrideWith(() => _StubBroadcastNotifier(state)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BroadcastScreen', () {
    testWidgets('idle layout — shows ordered stops and Save button',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          const BroadcastReady(names: ['Madina', 'Lapaz', 'Circle']),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Broadcast List'), findsOneWidget);
      expect(find.text('Madina'), findsOneWidget);
      expect(find.text('Lapaz'), findsOneWidget);
      expect(find.text('Circle'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('add — text field and Add button are present', (tester) async {
      await tester.pumpWidget(
        _buildScreen(const BroadcastReady(names: [])),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, ''), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('reorder — drag handle icon shown for each stop',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          const BroadcastReady(names: ['Madina', 'Lapaz', 'Circle']),
        ),
      );
      await tester.pumpAndSettle();

      // Each stop has an explicit drag-handle icon.
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
    });

    testWidgets(
        'save loading state — Save button disabled with progress indicator',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          const BroadcastReady(
              names: ['Madina', 'Lapaz'], isSaving: true),
        ),
      );
      // Use pump() — CircularProgressIndicator animates indefinitely.
      await tester.pump();

      final saveBtn = tester.widget<FilledButton>(
        find.byType(FilledButton).last,
      );
      expect(saveBtn.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('over-limit error — shows upgrade message in error banner',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          const BroadcastReady(
            names: ['Madina'],
            saveError: PlaceLimitError(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining("You've reached your broadcast limit"),
        findsOneWidget,
      );
    });
  });
}
