import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_error.dart';
import '../../../core/place_name_normalizer.dart';
import '../../me/presentation/me_notifier.dart';
import '../data/place_list_repository.dart';
import 'broadcast_notifier.dart';
import 'watch_notifier.dart';

/// Build a place list, then save as **watch** or **broadcast** and return to the map.
///
/// Enforces watch XOR broadcast: after saving one list, clears the other when permitted.
class PlacesSearchScreen extends ConsumerStatefulWidget {
  const PlacesSearchScreen({super.key});

  @override
  ConsumerState<PlacesSearchScreen> createState() => _PlacesSearchScreenState();
}

class _PlacesSearchScreenState extends ConsumerState<PlacesSearchScreen> {
  final _controller = TextEditingController();
  final _fieldFocus = FocusNode();

  final List<String> _names = [];
  bool _busy = false;
  String? _bannerError;

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _tryAdd() {
    final raw = _controller.text;
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
    _controller.clear();
    _fieldFocus.requestFocus();
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

  AppError _toAppError(Object? o) {
    if (o is AppError) return o;
    return const UnknownError('Something went wrong. Please try again.');
  }

  String _dioMessage(DioException e) => _toAppError(e.error).message;

  Future<void> _retryClearOpposite({required bool clearBroadcast}) async {
    final repo = ref.read(placeListRepositoryProvider);
    try {
      if (clearBroadcast) {
        await repo.putBroadcastList([]);
      } else {
        await repo.putWatchList([]);
      }
      ref.invalidate(watchNotifierProvider);
      ref.invalidate(broadcastNotifierProvider);
      if (mounted) context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_dioMessage(e)),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () =>
                _retryClearOpposite(clearBroadcast: clearBroadcast),
          ),
        ),
      );
    }
  }

  Future<void> _saveWatchMode() async {
    final snapshot = await ref.read(meNotifierProvider.future);
    if (snapshot == null) return;
    final me = snapshot.me;
    if (!me.permissions.contains('woleh.place.watch')) {
      if (mounted) context.push('/plans');
      return;
    }

    setState(() {
      _busy = true;
      _bannerError = null;
    });

    final repo = ref.read(placeListRepositoryProvider);
    try {
      await repo.putWatchList(List<String>.from(_names));
      if (me.permissions.contains('woleh.place.broadcast')) {
        try {
          await repo.putBroadcastList([]);
        } on DioException catch (e) {
          if (!mounted) return;
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Watch list saved, but clearing your broadcast route failed: '
                '${_dioMessage(e)}',
              ),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () =>
                    _retryClearOpposite(clearBroadcast: true),
              ),
            ),
          );
          return;
        }
      }
      ref.invalidate(watchNotifierProvider);
      ref.invalidate(broadcastNotifierProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      if (mounted) context.pop();
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

  Future<void> _saveBroadcastMode() async {
    final snapshot = await ref.read(meNotifierProvider.future);
    if (snapshot == null) return;
    final me = snapshot.me;
    if (!me.permissions.contains('woleh.place.broadcast')) {
      if (mounted) context.push('/plans');
      return;
    }

    setState(() {
      _busy = true;
      _bannerError = null;
    });

    final repo = ref.read(placeListRepositoryProvider);
    try {
      await repo.putBroadcastList(List<String>.from(_names));
      if (me.permissions.contains('woleh.place.watch')) {
        try {
          await repo.putWatchList([]);
        } on DioException catch (e) {
          if (!mounted) return;
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Broadcast list saved, but clearing your watch list failed: '
                '${_dioMessage(e)}',
              ),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () =>
                    _retryClearOpposite(clearBroadcast: false),
              ),
            ),
          );
          return;
        }
      }
      ref.invalidate(watchNotifierProvider);
      ref.invalidate(broadcastNotifierProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      if (mounted) context.pop();
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search places'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy ? null : () => context.pop(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _names.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Add place names in order (for a route, top = first stop). '
                        'Then choose how you want to use the list.',
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
                        key: ValueKey(name),
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
                    controller: _controller,
                    focusNode: _fieldFocus,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    maxLength: maxPlaceNameCodePoints,
                    decoration: const InputDecoration(
                      labelText: 'Place name',
                      hintText: 'e.g. Accra Central',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _tryAdd(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _busy ? null : _tryAdd,
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
                    onPressed: (_names.isEmpty || _busy) ? null : _saveWatchMode,
                    child: const Text('Show me buses'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed:
                        (_names.isEmpty || _busy) ? null : _saveBroadcastMode,
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
