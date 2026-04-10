import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/app_error.dart';
import '../data/place_list_repository.dart';

part 'watch_notifier.g.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

sealed class WatchState {
  const WatchState();
}

/// Initial server load (or refresh) in progress.
final class WatchLoading extends WatchState {
  const WatchLoading();
}

/// List is loaded and the editor is active.
final class WatchReady extends WatchState {
  const WatchReady({
    required this.names,
    this.isSaving = false,
    this.saveError,
    this.readOnlyOffline = false,
  });

  /// Display-form names in the current working set (not yet saved).
  final List<String> names;

  /// True while `putWatchList` is in flight.
  final bool isSaving;

  /// The last save error, cleared on the next successful save or add/remove.
  final AppError? saveError;

  /// Data was loaded from offline cache; mutations are disabled in the UI.
  final bool readOnlyOffline;

  // Sentinel object so that copyWith can distinguish "clear saveError" (pass
  // null) from "keep existing saveError" (omit the parameter).
  static const Object _noChange = Object();

  WatchReady copyWith({
    List<String>? names,
    bool? isSaving,
    Object? saveError = _noChange,
    bool? readOnlyOffline,
  }) {
    return WatchReady(
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
final class WatchLoadError extends WatchState {
  const WatchLoadError({required this.message, this.isOffline = false});

  final String message;
  final bool isOffline;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

@riverpod
class WatchNotifier extends _$WatchNotifier {
  @override
  WatchState build() {
    _load();
    return const WatchLoading();
  }

  Future<void> _load() async {
    state = const WatchLoading();
    try {
      final snapshot =
          await ref.read(placeListRepositoryProvider).getWatchList();
      state = WatchReady(
        names: snapshot.names,
        readOnlyOffline: snapshot.fromCache,
      );
    } on OfflineError catch (e) {
      state = WatchLoadError(message: e.message, isOffline: true);
    } on DioException catch (e) {
      state = WatchLoadError(message: _extractMessage(e.error));
    } catch (_) {
      state = const WatchLoadError(
          message: 'Could not load your watch list. Please try again.');
    }
  }

  /// Appends [name] to the working list; clears any previous save error.
  void add(String name) {
    final ready = state as WatchReady?;
    if (ready == null || ready.readOnlyOffline || name.trim().isEmpty) return;
    state = ready.copyWith(
      names: [...ready.names, name.trim()],
      saveError: null,
    );
  }

  /// Removes the first occurrence of [name] from the working list.
  void remove(String name) {
    final ready = state as WatchReady?;
    if (ready == null || ready.readOnlyOffline) return;
    state = ready.copyWith(
      names: ready.names.where((n) => n != name).toList(),
    );
  }

  /// Sends the current working list to the server via `putWatchList`.
  ///
  /// On success, refreshes state from the server-returned list.
  /// On failure, stores a typed [AppError] on [WatchReady.saveError].
  Future<void> save() async {
    final ready = state as WatchReady?;
    if (ready == null || ready.isSaving || ready.readOnlyOffline) return;
    state = ready.copyWith(isSaving: true, saveError: null);
    try {
      final saved = await ref
          .read(placeListRepositoryProvider)
          .putWatchList(ready.names);
      state = WatchReady(names: saved, readOnlyOffline: false);
    } on DioException catch (e) {
      final appError = _toAppError(e.error);
      state = (state as WatchReady).copyWith(
        isSaving: false,
        saveError: appError,
      );
    } catch (_) {
      state = (state as WatchReady).copyWith(
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
