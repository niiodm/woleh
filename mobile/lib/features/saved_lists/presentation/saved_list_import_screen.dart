import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics_provider.dart';
import '../../../core/app_error.dart';
import '../../me/presentation/me_notifier.dart';
import '../data/saved_place_list_dto.dart';
import '../data/saved_place_list_repository.dart';
import 'saved_list_session.dart';
import 'saved_list_user_message.dart';
import 'saved_place_list_summaries_provider.dart';
import 'watch_broadcast_limits.dart';

/// Preview a shared list (public API) and optionally save, watch, or broadcast.
class SavedListImportScreen extends ConsumerStatefulWidget {
  const SavedListImportScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<SavedListImportScreen> createState() =>
      _SavedListImportScreenState();
}

class _SavedListImportScreenState extends ConsumerState<SavedListImportScreen> {
  AsyncValue<SavedPlaceListPublicDto> _data = const AsyncLoading();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _data = const AsyncLoading());
    try {
      final dto =
          await ref.read(savedPlaceListRepositoryProvider).getPublicByToken(
                widget.token,
              );
      if (!mounted) return;
      setState(() => _data = AsyncData(dto));
    } on SavedListNotFoundError catch (_) {
      if (!mounted) return;
      setState(
        () => _data = AsyncError(
          'This list link is invalid or has been removed.',
          StackTrace.empty,
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _data = AsyncError(e, st));
    }
  }

  AppError _toAppError(Object? o) {
    if (o is AppError) return o;
    return const UnknownError('Something went wrong. Please try again.');
  }

  String _dioMessage(DioException e) => _toAppError(e.error).message;

  String _title(SavedPlaceListPublicDto dto) =>
      dto.title?.trim().isNotEmpty == true ? dto.title!.trim() : 'Shared list';

  /// Prefer [pop] so routes under import (e.g. `/home` → saved lists) stay in the stack.
  void _closeImport() {
    if (!context.mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _saveCopy(SavedPlaceListPublicDto dto) async {
    setState(() => _busy = true);
    final repo = ref.read(savedPlaceListRepositoryProvider);
    try {
      await repo.create(
        title: dto.title,
        names: List<String>.from(dto.names),
      );
      ref.invalidate(savedPlaceListSummariesProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      unawaited(
        ref.read(wolehAnalyticsProvider).logEvent('saved_list_import_saved', {
          'place_count': dto.names.length,
        }),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to your lists')),
      );
      _closeImport();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_dioMessage(e))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(savedListUserMessage(e))),
      );
    }
  }

  Future<void> _watch(SavedPlaceListPublicDto dto) async {
    if (dto.names.isEmpty) return;
    setState(() => _busy = true);
    final ok = await applyWatchSessionFromNames(
      ref: ref,
      context: context,
      names: List<String>.from(dto.names),
      onSuccess: () {
        if (mounted) context.go('/home');
      },
    );
    if (mounted) setState(() => _busy = false);
    if (ok) {
      unawaited(
        ref.read(wolehAnalyticsProvider).logEvent(
          'session_started_from_saved_list',
          const {'mode': 'watch', 'source': 'import'},
        ),
      );
    }
  }

  Future<void> _broadcast(SavedPlaceListPublicDto dto) async {
    if (dto.names.isEmpty) return;
    setState(() => _busy = true);
    final ok = await applyBroadcastSessionFromNames(
      ref: ref,
      context: context,
      names: List<String>.from(dto.names),
      onSuccess: () {
        if (mounted) context.go('/home');
      },
    );
    if (mounted) setState(() => _busy = false);
    if (ok) {
      unawaited(
        ref.read(wolehAnalyticsProvider).logEvent(
          'session_started_from_saved_list',
          const {'mode': 'broadcast', 'source': 'import'},
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(meNotifierProvider).valueOrNull;
    final maxNames =
        snapshot == null ? null : savedListMaxPlaceNames(snapshot.me);
    final canWatch =
        snapshot?.me.permissions.contains('woleh.place.watch') ?? false;
    final canBroadcast =
        snapshot?.me.permissions.contains('woleh.place.broadcast') ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import list'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : _closeImport,
        ),
      ),
      body: _data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        e is String ? e : savedListUserMessage(e),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (dto) {
                final title = _title(dto);
                final overPlan =
                    maxNames != null && dto.names.length > maxNames;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy) const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${dto.names.length} places',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          if (overPlan) ...[
                            const SizedBox(height: 12),
                            Text(
                              'This list has more places than your plan allows '
                              'for a single route ($maxNames). Save a copy may '
                              'fail until you shorten the list or upgrade.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          ...dto.names.map(
                            (n) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.place_outlined),
                              title: Text(n),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.tonal(
                              onPressed: _busy || dto.names.isEmpty
                                  ? null
                                  : () => _saveCopy(dto),
                              child: const Text('Save to my lists'),
                            ),
                            if (canWatch) ...[
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _busy || dto.names.isEmpty
                                    ? null
                                    : () => _watch(dto),
                                child: const Text('Show me buses'),
                              ),
                            ],
                            if (canBroadcast) ...[
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _busy || dto.names.isEmpty
                                    ? null
                                    : () => _broadcast(dto),
                                child: const Text('Show me passengers'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
