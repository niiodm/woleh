import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ws_client.dart';

/// Slim banner for WebSocket connectivity (NFR-2). Hidden when connected or
/// still in the initial connect attempt before any server data arrives.
class WsStatusBanner extends ConsumerWidget {
  const WsStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(wsClientProvider);
    final ws = ref.read(wsClientProvider.notifier);
    return WsStatusBannerCore(
      listenable: ws.connectionState,
      onRetry: ws.retryConnection,
    );
  }
}

/// Core banner driven by a [ValueNotifier] — use directly in widget tests.
class WsStatusBannerCore extends StatelessWidget {
  const WsStatusBannerCore({
    super.key,
    required this.listenable,
    required this.onRetry,
  });

  final ValueNotifier<WsConnectionState> listenable;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WsConnectionState>(
      valueListenable: listenable,
      builder: (context, state, _) {
        if (state == WsConnectionState.connected ||
            state == WsConnectionState.connecting) {
          return const SizedBox.shrink();
        }

        final scheme = Theme.of(context).colorScheme;
        final isReconnecting = state == WsConnectionState.reconnecting;

        return Material(
          color: scheme.errorContainer.withValues(alpha: 0.9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.wifi_off_outlined,
                  size: 20,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isReconnecting
                        ? 'Live updates unavailable — reconnecting…'
                        : 'Live updates offline',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                if (!isReconnecting)
                  TextButton(
                    onPressed: onRetry,
                    child: Text(
                      'Retry',
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
