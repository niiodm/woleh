import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_error.dart';
import '../../me/presentation/me_notifier.dart';
import '../../places/data/place_list_repository.dart';
import '../../places/presentation/broadcast_notifier.dart';
import '../../places/presentation/watch_notifier.dart';

AppError _toAppError(Object? o) {
  if (o is AppError) return o;
  return const UnknownError('Something went wrong. Please try again.');
}

String _dioMessage(DioException e) => _toAppError(e.error).message;

/// Applies [names] as the active **watch** list and clears broadcast when allowed
/// (same rules as [PlacesSearchScreen]).
Future<bool> applyWatchSessionFromNames({
  required WidgetRef ref,
  required BuildContext context,
  required List<String> names,
  VoidCallback? onSuccess,
}) async {
  final snapshot = await ref.read(meNotifierProvider.future);
  if (snapshot == null) return false;
  final me = snapshot.me;
  if (!me.permissions.contains('woleh.place.watch')) {
    if (context.mounted) context.push('/plans');
    return false;
  }

  final repo = ref.read(placeListRepositoryProvider);
  try {
    await repo.putWatchList(List<String>.from(names));
    if (me.permissions.contains('woleh.place.broadcast')) {
      try {
        await repo.putBroadcastList([]);
      } on DioException catch (e) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Watch list saved, but clearing your broadcast route failed: '
              '${_dioMessage(e)}',
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => unawaited(_retryClearOpposite(
                ref: ref,
                context: context,
                clearBroadcast: true,
                onSuccess: onSuccess,
              )),
            ),
          ),
        );
        return false;
      }
    }
    ref.invalidate(watchNotifierProvider);
    ref.invalidate(broadcastNotifierProvider);
    onSuccess?.call();
    return true;
  } on DioException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_dioMessage(e))),
      );
    }
    return false;
  }
}

/// Applies [names] as the active **broadcast** list and clears watch when allowed.
Future<bool> applyBroadcastSessionFromNames({
  required WidgetRef ref,
  required BuildContext context,
  required List<String> names,
  VoidCallback? onSuccess,
}) async {
  final snapshot = await ref.read(meNotifierProvider.future);
  if (snapshot == null) return false;
  final me = snapshot.me;
  if (!me.permissions.contains('woleh.place.broadcast')) {
    if (context.mounted) context.push('/plans');
    return false;
  }

  final repo = ref.read(placeListRepositoryProvider);
  try {
    await repo.putBroadcastList(List<String>.from(names));
    if (me.permissions.contains('woleh.place.watch')) {
      try {
        await repo.putWatchList([]);
      } on DioException catch (e) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Broadcast list saved, but clearing your watch list failed: '
              '${_dioMessage(e)}',
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => unawaited(
                _retryClearOpposite(
                  ref: ref,
                  context: context,
                  clearBroadcast: false,
                  onSuccess: onSuccess,
                ),
              ),
            ),
          ),
        );
        return false;
      }
    }
    ref.invalidate(watchNotifierProvider);
    ref.invalidate(broadcastNotifierProvider);
    onSuccess?.call();
    return true;
  } on DioException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_dioMessage(e))),
      );
    }
    return false;
  }
}

Future<void> _retryClearOpposite({
  required WidgetRef ref,
  required BuildContext context,
  required bool clearBroadcast,
  VoidCallback? onSuccess,
}) async {
  final repo = ref.read(placeListRepositoryProvider);
  try {
    if (clearBroadcast) {
      await repo.putBroadcastList([]);
    } else {
      await repo.putWatchList([]);
    }
    ref.invalidate(watchNotifierProvider);
    ref.invalidate(broadcastNotifierProvider);
    if (context.mounted) onSuccess?.call();
  } on DioException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_dioMessage(e))),
    );
  }
}
