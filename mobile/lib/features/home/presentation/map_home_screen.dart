import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_error.dart';
import '../../../core/firebase_monitoring.dart';
import '../../../core/ws_message.dart';
import '../../../shared/ws_status_banner.dart';
import '../../location/presentation/live_map_stack.dart';
import '../../me/presentation/me_notifier.dart';
import '../../places/data/place_list_repository.dart';
import '../../places/presentation/broadcast_notifier.dart';
import '../../places/presentation/match_notifier.dart';
import '../../places/presentation/watch_notifier.dart';

/// Full-screen map with search entry, profile, WS status, and match toasts.
class MapHomeScreen extends ConsumerStatefulWidget {
  const MapHomeScreen({super.key});

  @override
  ConsumerState<MapHomeScreen> createState() => _MapHomeScreenState();
}

enum _ActivePlaceMode { broadcast, watch }

/// Strong red for the destructive “stop” control (readable on `surfaceContainerHigh`).
const _kStopButtonRed = Color(0xFFE53935);

class _MapHomeScreenState extends ConsumerState<MapHomeScreen> {
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    if (!firebaseCustomPerformanceEnabled) return;
    try {
      final trace = FirebasePerformance.instance.newTrace('map_home_first_frame');
      unawaited(trace.start());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(trace.stop());
      });
    } catch (_) {}
  }

  AppError _toAppError(Object? o) {
    if (o is AppError) return o;
    return const UnknownError('Something went wrong. Please try again.');
  }

  String _dioMessage(DioException e) => _toAppError(e.error).message;

  _ActivePlaceMode? _activeStopMode(WatchState watch, BroadcastState broadcast) {
    final br = broadcast is BroadcastReady ? broadcast : null;
    if (br != null &&
        br.names.isNotEmpty &&
        !br.readOnlyOffline) {
      return _ActivePlaceMode.broadcast;
    }
    final wr = watch is WatchReady ? watch : null;
    if (wr != null &&
        wr.names.isNotEmpty &&
        !wr.readOnlyOffline) {
      return _ActivePlaceMode.watch;
    }
    return null;
  }

  String _stopTooltip(_ActivePlaceMode mode) => switch (mode) {
        _ActivePlaceMode.broadcast => 'Stop broadcasting',
        _ActivePlaceMode.watch => 'Stop watching',
      };

  Future<void> _stopActive(_ActivePlaceMode mode) async {
    if (_stopping) return;
    final snapshot = await ref.read(meNotifierProvider.future);
    if (snapshot == null || !mounted) return;
    final me = snapshot.me;
    if (mode == _ActivePlaceMode.broadcast &&
        !me.permissions.contains('woleh.place.broadcast')) {
      if (mounted) context.push('/plans');
      return;
    }
    if (mode == _ActivePlaceMode.watch &&
        !me.permissions.contains('woleh.place.watch')) {
      if (mounted) context.push('/plans');
      return;
    }

    setState(() => _stopping = true);
    final repo = ref.read(placeListRepositoryProvider);
    try {
      if (mode == _ActivePlaceMode.broadcast) {
        await repo.putBroadcastList([]);
      } else {
        await repo.putWatchList([]);
      }
      ref.invalidate(watchNotifierProvider);
      ref.invalidate(broadcastNotifierProvider);
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_dioMessage(e))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not stop. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

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

    final watchState = ref.watch(watchNotifierProvider);
    final broadcastState = ref.watch(broadcastNotifierProvider);
    final stopMode = _activeStopMode(watchState, broadcastState);

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
                      if (stopMode != null) ...[
                        const SizedBox(width: 8),
                        Material(
                          elevation: 2,
                          shadowColor: Colors.black26,
                          shape: const CircleBorder(),
                          color: scheme.surfaceContainerHigh,
                          child: IconButton(
                            tooltip: _stopTooltip(stopMode),
                            onPressed: _stopping
                                ? null
                                : () => _stopActive(stopMode),
                            icon: _stopping
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _kStopButtonRed,
                                    ),
                                  )
                                : const Icon(
                                    Icons.stop_circle_outlined,
                                    color: _kStopButtonRed,
                                  ),
                          ),
                        ),
                      ],
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
