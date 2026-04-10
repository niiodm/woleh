import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:odm_clarity_woleh_mobile/core/app_error.dart';
import 'package:odm_clarity_woleh_mobile/features/places/presentation/watch_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/places/presentation/watch_screen.dart';

// ---------------------------------------------------------------------------
// Stub notifier
// ---------------------------------------------------------------------------

class _StubWatchNotifier extends WatchNotifier {
  _StubWatchNotifier(this._initialState);

  final WatchState _initialState;

  @override
  WatchState build() => _initialState;
}

// ---------------------------------------------------------------------------
// Test helper
// ---------------------------------------------------------------------------

Widget _buildScreen(WatchState state) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const WatchScreen(),
      ),
      GoRoute(
        path: '/plans',
        builder: (_, __) => const Scaffold(body: Text('Plans')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      watchNotifierProvider.overrideWith(() => _StubWatchNotifier(state)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('WatchScreen', () {
    testWidgets('idle layout — shows names and Save button', (tester) async {
      await tester.pumpWidget(
        _buildScreen(const WatchReady(names: ['Madina', 'Lapaz'])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Watch List'), findsOneWidget);
      expect(find.text('Madina'), findsOneWidget);
      expect(find.text('Lapaz'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('add name — text field and Add button are present',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(const WatchReady(names: [])),
      );
      await tester.pumpAndSettle();

      // The "Add a place name" field is present.
      expect(find.widgetWithText(TextField, ''), findsOneWidget);
      // The "+" add button is present.
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('add name — entering text shows normalized preview',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(const WatchReady(names: [])),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ACCRA CENTRAL');
      await tester.pump();

      // The normalized preview should appear beneath the field.
      expect(find.textContaining('accra central'), findsOneWidget);
    });

    testWidgets('remove name — close button is shown per name', (tester) async {
      await tester.pumpWidget(
        _buildScreen(const WatchReady(names: ['Madina', 'Circle'])),
      );
      await tester.pumpAndSettle();

      // Each name tile has a remove (close) icon button.
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    });

    testWidgets('save loading state — Save button is disabled with progress indicator',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(const WatchReady(names: ['Madina'], isSaving: true)),
      );
      // Use pump() not pumpAndSettle(): CircularProgressIndicator animates
      // forever and would cause pumpAndSettle() to time out.
      await tester.pump();

      // Save button is disabled while saving — its onPressed is null.
      final saveBtn = tester.widget<FilledButton>(
        find.byType(FilledButton).last,
      );
      expect(saveBtn.onPressed, isNull);

      // A CircularProgressIndicator is rendered inside the button.
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('over-limit error — shows upgrade message in error banner',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          const WatchReady(
            names: ['Madina', 'Lapaz', 'Circle', 'Kaneshie', 'Achimota'],
            saveError: PlaceLimitError(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining("You've reached your watch limit"),
        findsOneWidget,
      );
    });

    testWidgets('empty-list state — shows placeholder text', (tester) async {
      await tester.pumpWidget(
        _buildScreen(const WatchReady(names: [])),
      );
      await tester.pumpAndSettle();

      expect(find.text('No places yet'), findsOneWidget);
      expect(find.textContaining('Add place names above'), findsOneWidget);
    });
  });
}
