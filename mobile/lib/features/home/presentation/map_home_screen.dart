import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ws_message.dart';
import '../../../shared/ws_status_banner.dart';
import '../../location/presentation/live_map_stack.dart';
import '../../places/presentation/match_notifier.dart';

/// Full-screen map with search entry, profile, WS status, and match toasts.
class MapHomeScreen extends ConsumerStatefulWidget {
  const MapHomeScreen({super.key});

  @override
  ConsumerState<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends ConsumerState<MapHomeScreen> {
  @override
  Widget build(BuildContext context) {
    ref.listen<List<MatchMessage>>(matchNotifierProvider, (prev, next) {
      if (next.isEmpty) return;
      final isNew = prev == null || prev.isEmpty || next.first != prev.first;
      if (!isNew) return;
      final msg = next.first;
      final names = msg.matchedNames.join(', ');
      final isWatcher = msg.kind == 'watcher';
      final text = isWatcher
          ? 'Match — a bus is heading through: $names'
          : 'Match — a watcher needs: $names';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
    });

    // Keep the notifier subscribed while on the map.
    ref.watch(matchNotifierProvider);

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: LiveMapStack(forMapHome: true)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const WsStatusBanner(),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Material(
                          elevation: 2,
                          shadowColor: Colors.black26,
                          borderRadius: BorderRadius.circular(28),
                          color: scheme.surfaceContainerHigh,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(28),
                            onTap: () => context.push('/places/search'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Search places',
                                      style: textTheme.bodyLarge?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        elevation: 2,
                        shadowColor: Colors.black26,
                        shape: const CircleBorder(),
                        color: scheme.surfaceContainerHigh,
                        child: IconButton(
                          tooltip: 'Profile',
                          icon: Icon(
                            Icons.person_outline,
                            color: scheme.primary,
                          ),
                          onPressed: () => context.push('/profile'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
