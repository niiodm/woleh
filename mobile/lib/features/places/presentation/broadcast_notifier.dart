import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/app_error.dart';
import '../data/place_list_repository.dart';

part 'broadcast_notifier.g.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

sealed class BroadcastState {
  const BroadcastState();
}

/// Initial server load (or refresh) in progress.
final class BroadcastLoading extends BroadcastState {
  const BroadcastLoading();
}

/// List is loaded and the editor is active.
///
/// The list is **ordered** — position matters for the drive-through sequence.
final class BroadcastReady extends BroadcastState {
  const BroadcastReady({
    required this.names,
    this.isSaving = false,
    this.saveError,
    this.readOnlyOffline = false,
  });

  /// Display-form names in the current working set (not yet saved).
  final List<String> names;

  /// True while `putBroadcastList` is in flight.
  final bool isSaving;

  /// The last save error, cleared on the next successful save or edit.
  final AppError? saveError;

  /// Data was loaded from offline cache; mutations are disabled in the UI.
  final bool readOnlyOffline;

  static const Object _noChange = Object();

  BroadcastReady copyWith({
    List<String>? names,
    bool? isSaving,
    Object? saveError = _noChange,
    bool? readOnlyOffline,
  }) {
    return BroadcastReady(
      names: names ?? this.names,
      isSaving: isSaving ?? this.isSaving,
      saveError: identical(saveError, _noChange)
          ? this.saveError
          : saveError as AppError?,
      readOnlyOffline: readOnlyOffline ?? this.readOnlyOffline,
    );
  }
}

/// Initial server load failed.
final class BroadcastLoadError extends BroadcastState {
  const BroadcastLoadError({required this.message, this.isOffline = false});

  final String message;
  final bool isOffline;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

@riverpod
class BroadcastNotifier extends _$BroadcastNotifier {
  @override
  BroadcastState build() {
    _load();
    return const BroadcastLoading();
  }

  Future<void> _load() async {
    state = const BroadcastLoading();
    try {
      final snapshot =
          await ref.read(placeListRepositoryProvider).getBroadcastList();
      state = BroadcastReady(
        names: snapshot.names,
        readOnlyOffline: snapshot.fromCache,
      );
    } on OfflineError catch (e) {
      state = BroadcastLoadError(message: e.message, isOffline: true);
    } on DioException catch (e) {
      state = BroadcastLoadError(message: _extractMessage(e.error));
    } catch (_) {
      state = const BroadcastLoadError(
          message: 'Could not load your broadcast list. Please try again.');
    }
  }

  /// Appends [name] to the end of the ordered working list; clears any
  /// previous save error.
  void add(String name) {
    final ready = state as BroadcastReady?;
    if (ready == null || ready.readOnlyOffline || name.trim().isEmpty) return;
    state = ready.copyWith(
      names: [...ready.names, name.trim()],
      saveError: null,
    );
  }

  /// Removes the first occurrence of [name] from the working list.
  void remove(String name) {
    final ready = state as BroadcastReady?;
    if (ready == null || ready.readOnlyOffline) return;
    state = ready.copyWith(
      names: ready.names.where((n) => n != name).toList(),
    );
  }

  /// Reorders a stop from [oldIndex] to [newIndex].
  ///
  /// Use directly as the `onReorder` callback of [ReorderableListView]
  /// (Flutter adjusts [newIndex] before firing the callback, so no
  /// adjustment is needed here).
  void reorder(int oldIndex, int newIndex) {
    final ready = state as BroadcastReady?;
    if (ready == null || ready.readOnlyOffline) return;
    // ReorderableListView passes a post-removal newIndex when moving downward,
    // so subtract 1 to compensate before re-inserting.
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final names = [...ready.names];
    final item = names.removeAt(oldIndex);
    names.insert(adjusted, item);
    state = ready.copyWith(names: names);
  }

  /// Sends the current ordered working list to the server via
  /// `putBroadcastList`.
  ///
  /// On success, refreshes state from the server-returned list.
  /// On failure, stores a typed [AppError] on [BroadcastReady.saveError].
  Future<void> save() async {
    final ready = state as BroadcastReady?;
    if (ready == null || ready.isSaving || ready.readOnlyOffline) return;
    state = ready.copyWith(isSaving: true, saveError: null);
    try {
      final saved = await ref
          .read(placeListRepositoryProvider)
          .putBroadcastList(ready.names);
      state = BroadcastReady(names: saved, readOnlyOffline: false);
    } on DioException catch (e) {
      final appError = _toAppError(e.error);
      state = (state as BroadcastReady).copyWith(
        isSaving: false,
        saveError: appError,
      );
    } catch (_) {
      state = (state as BroadcastReady).copyWith(
        isSaving: false,
        saveError: const UnknownError('Could not save. Please try again.'),
      );
    }
  }

  /// Reloads the list from the server.
  Future<void> refresh() => _load();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppError _toAppError(Object? error) {
  if (error is AppError) return error;
  return const UnknownError('Something went wrong. Please try again.');
}

String _extractMessage(Object? error) => _toAppError(error).message;
