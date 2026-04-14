import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics_provider.dart';
import '../../../core/app_error.dart';
import '../../../core/place_name_normalizer.dart';
import '../../me/data/me_dto.dart';
import '../../me/presentation/me_notifier.dart';
import '../data/saved_place_list_repository.dart';
import 'saved_list_session.dart';
import 'saved_place_list_summaries_provider.dart';
import 'watch_broadcast_limits.dart';

/// Create or edit a persisted saved place list; optional one-tap watch/broadcast.
class SavedListEditorScreen extends ConsumerStatefulWidget {
  const SavedListEditorScreen({super.key, this.listId});

  /// `null` = create; otherwise load and update this id.
  final int? listId;

  @override
  ConsumerState<SavedListEditorScreen> createState() =>
      _SavedListEditorScreenState();
}

class _SavedListEditorScreenState extends ConsumerState<SavedListEditorScreen> {
  final _titleController = TextEditingController();
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();

  final List<String> _names = [];
  bool _loading = true;
  bool _busy = false;
  String? _bannerError;

  @override
  void initState() {
    super.initState();
    if (widget.listId == null) {
      _loading = false;
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final id = widget.listId;
    if (id == null) return;
    try {
      final detail =
          await ref.read(savedPlaceListRepositoryProvider).getDetail(id);
      if (!mounted) return;
      setState(() {
        _titleController.text = detail.title ?? '';
        _names
          ..clear()
          ..addAll(detail.names);
        _loading = false;
        _bannerError = null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _bannerError = _dioMessage(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _bannerError = 'Could not load this list.';
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  AppError _toAppError(Object? o) {
    if (o is AppError) return o;
    return const UnknownError('Something went wrong. Please try again.');
  }

  String _dioMessage(DioException e) => _toAppError(e.error).message;

  int _maxNamesForMe(MeLoadSnapshot snapshot) =>
      savedListMaxPlaceNames(snapshot.me);

  void _tryAdd(int maxNames) {
    unawaited(
      ref.read(wolehAnalyticsProvider).logButtonTapped(
            'saved_list_add_place',
            screenName: '/saved-lists/edit',
          ),
    );
    if (_names.length >= maxNames) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can add at most $maxNames places on your plan.',
          ),
        ),
      );
      return;
    }
    final raw = _nameController.text;
    final validation = validatePlaceName(raw);
    if (validation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validation)),
      );
      return;
    }
    final trimmed = raw.trim();
    final norm = normalizePlaceName(trimmed);
    if (_names.any((n) => normalizePlaceName(n) == norm)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That place is already in the list')),
      );
      return;
    }
    setState(() {
      _names.add(trimmed);
      _bannerError = null;
    });
    _nameController.clear();
    _nameFocus.requestFocus();
  }

  void _removeAt(int index) {
    setState(() {
      _names.removeAt(index);
      _bannerError = null;
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _names.removeAt(oldIndex);
      _names.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final titleOrNull = title.isEmpty ? null : title;
    if (_names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one place.')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _bannerError = null;
    });

    final repo = ref.read(savedPlaceListRepositoryProvider);
    try {
      if (widget.listId == null) {
        await repo.create(title: titleOrNull, names: List<String>.from(_names));
      } else {
        await repo.replace(
          id: widget.listId!,
          title: titleOrNull,
          names: List<String>.from(_names),
        );
      }
      ref.invalidate(savedPlaceListSummariesProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      unawaited(
        ref.read(wolehAnalyticsProvider).logEvent('saved_list_saved', {
          'place_count': _names.length,
          'is_create': widget.listId == null,
        }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('List saved')),
        );
        context.pop();
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _bannerError = _dioMessage(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _bannerError = 'Could not save. Please try again.';
      });
    }
  }

  Future<void> _startWatch() async {
    if (_names.isEmpty) return;
    setState(() => _busy = true);
    final ok = await applyWatchSessionFromNames(
      ref: ref,
      context: context,
      names: List<String>.from(_names),
      onSuccess: () {
        if (mounted) context.go('/home');
      },
    );
    if (mounted) setState(() => _busy = false);
    if (ok) {
      unawaited(
        ref.read(wolehAnalyticsProvider).logButtonTapped(
              'saved_list_start_watch',
              screenName: '/saved-lists/edit',
            ),
      );
    }
  }

  Future<void> _startBroadcast() async {
    if (_names.isEmpty) return;
    setState(() => _busy = true);
    final ok = await applyBroadcastSessionFromNames(
      ref: ref,
      context: context,
      names: List<String>.from(_names),
      onSuccess: () {
        if (mounted) context.go('/home');
      },
    );
    if (mounted) setState(() => _busy = false);
    if (ok) {
      unawaited(
        ref.read(wolehAnalyticsProvider).logButtonTapped(
              'saved_list_start_broadcast',
              screenName: '/saved-lists/edit',
            ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final snapshot = ref.watch(meNotifierProvider).valueOrNull;
    final maxNames = snapshot == null ? 32 : _maxNamesForMe(snapshot);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.listId == null ? 'New list' : 'Edit list'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_bannerError != null && widget.listId != null && _names.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit list')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_bannerError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _bannerError = null;
                      _loading = true;
                    });
                    unawaited(_load());
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.listId == null ? 'New list' : 'Edit list'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _titleController,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title (optional)',
                hintText: 'e.g. Morning commute',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _names.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Add place names in order. Save as a reusable list, '
                        'or start watch / broadcast with this route.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _names.length,
                    onReorder: _onReorder,
                    itemBuilder: (context, index) {
                      final name = _names[index];
                      return ListTile(
                        key: ValueKey('$name-$index'),
                        title: Text(name),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy ? null : () => _removeAt(index),
                          tooltip: 'Remove',
                        ),
                      );
                    },
                  ),
          ),
          if (_bannerError != null)
            Material(
              color: scheme.errorContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  _bannerError!,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    maxLength: maxPlaceNameCodePoints,
                    decoration: InputDecoration(
                      labelText: 'Place name',
                      hintText: 'Up to $maxNames places',
                      border: const OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _tryAdd(maxNames),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _busy ? null : () => _tryAdd(maxNames),
                  icon: const Icon(Icons.add),
                  tooltip: 'Add to list',
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: (_names.isEmpty || _busy) ? null : _startWatch,
                    child: const Text('Show me buses'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed:
                        (_names.isEmpty || _busy) ? null : _startBroadcast,
                    child: const Text('Show me passengers'),
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
