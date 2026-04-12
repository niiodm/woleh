import 'presentation/broadcast_notifier.dart';
import 'presentation/watch_notifier.dart';

/// True when map home would treat the user as having an active watch or
/// broadcast session: non-empty list and not read-only offline cache.
bool hasActivePlaceSession(WatchState watch, BroadcastState broadcast) {
  final br = broadcast is BroadcastReady ? broadcast : null;
  if (br != null && br.names.isNotEmpty && !br.readOnlyOffline) {
    return true;
  }
  final wr = watch is WatchReady ? watch : null;
  if (wr != null && wr.names.isNotEmpty && !wr.readOnlyOffline) {
    return true;
  }
  return false;
}
