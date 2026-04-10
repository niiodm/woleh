import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth_state.dart';
import '../../../core/ws_client.dart';
import '../../../core/ws_message.dart';

part 'match_notifier.g.dart';

/// Accumulates incoming [MatchMessage]s from the WebSocket stream.
///
/// State is a list of up to [_cap] most-recent matches (newest first).
/// Clears automatically on sign-out.
@Riverpod(keepAlive: true)
class MatchNotifier extends _$MatchNotifier {
  static const _cap = 20;

  StreamSubscription<WsMessage>? _sub;

  @override
  List<MatchMessage> build() {
    _sub?.cancel();
    _sub = ref.read(wsClientProvider.notifier).messages.listen((msg) {
      if (msg is! MatchMessage) return;
      final next = [msg, ...state];
      state = next.length > _cap ? next.sublist(0, _cap) : next;
    });

    // Clear the list when the user signs out.
    ref.listen<AsyncValue<String?>>(
      authStateProvider,
      (_, next) {
        if (next.valueOrNull == null) state = const [];
      },
    );

    ref.onDispose(() => _sub?.cancel());

    return const [];
  }

  /// Removes the match at [index] (e.g. user dismissed the card).
  void dismiss(int index) {
    final next = [...state]..removeAt(index);
    state = next;
  }
}
