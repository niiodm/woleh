import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth_state.dart';
import '../../../core/location/location_fix.dart';
import '../../../core/location/location_source.dart';
import '../../../core/location/location_source_provider.dart';
import '../../me/data/me_dto.dart';
import '../../me/data/me_repository.dart';
import '../../me/presentation/me_notifier.dart';

part 'location_publish_notifier.g.dart';

/// When `false`, stop the position stream (app backgrounded / engine torn down).
///
/// [AppLifecycleState.inactive] stays subscribed (transient overlays, task switcher).
@visibleForTesting
bool locationPublishLifecycleAllowsStream(AppLifecycleState? state) {
  switch (state) {
    case null:
    case AppLifecycleState.resumed:
    case AppLifecycleState.inactive:
      return true;
    case AppLifecycleState.hidden:
    case AppLifecycleState.paused:
    case AppLifecycleState.detached:
      return false;
  }
}

/// Foreground GPS → throttled `POST /api/v1/me/location` ([`MAP_LIVE_LOCATION_PLAN.md`](../../../../../docs/MAP_LIVE_LOCATION_PLAN.md) §4.3).
///
/// Subscribes only when the user is signed in, has watch or broadcast permission,
/// and `locationSharingEnabled` is true. Pauses when the app is not in a
/// foreground-eligible lifecycle state.
///
/// [state] is the latest device fix for map UI (§4.4); cleared when not publishing.
@Riverpod(keepAlive: true)
class LocationPublishNotifier extends _$LocationPublishNotifier {
  /// Aligns with server default `LOCATION_PUBLISH_MIN_INTERVAL_MS` (~1 Hz).
  static const minPostInterval = Duration(milliseconds: 1000);

  /// Reposts the last fix on this interval while stationary (stream may be quiet).
  static const heartbeatInterval = Duration(seconds: 5);

  StreamSubscription<LocationFix>? _posSub;
  Timer? _heartbeat;
  _AppLifecycleBinding? _lifecycle;
  bool _foreground = true;
  bool _disposed = false;
  DateTime? _lastSentAt;

  @override
  LocationFix? build() {
    _disposed = false;
    _foreground = locationPublishLifecycleAllowsStream(
      WidgetsBinding.instance.lifecycleState,
    );

    ref.listen<AsyncValue<String?>>(
      authStateProvider,
      (_, __) => unawaited(_syncSubscription()),
    );

    ref.listen<AsyncValue<MeLoadSnapshot?>>(
      meNotifierProvider,
      (_, __) => unawaited(_syncSubscription()),
    );

    _lifecycle = _AppLifecycleBinding(_onLifecycleChanged);
    _lifecycle!.attach();

    ref.onDispose(() {
      _disposed = true;
      _cancelHeartbeat();
      _stopPositionStream(resetThrottle: true);
      _lifecycle?.detach();
      _lifecycle = null;
    });

    unawaited(_syncSubscription());

    return null;
  }

  void _onLifecycleChanged(AppLifecycleState state) {
    final allow = locationPublishLifecycleAllowsStream(state);
    if (allow == _foreground) return;
    _foreground = allow;
    if (allow) {
      unawaited(_syncSubscription());
    } else {
      _stopPositionStream(resetThrottle: true);
    }
  }

  Future<void> _syncSubscription() async {
    _cancelHeartbeat();
    _posSub?.cancel();
    _posSub = null;

    if (_disposed || !_foreground) {
      _lastSentAt = null;
      state = null;
      return;
    }
    if (ref.read(authStateProvider).valueOrNull == null) {
      _lastSentAt = null;
      state = null;
      return;
    }

    final snap = ref.read(meNotifierProvider).valueOrNull;
    if (snap == null) return;
    final me = snap.me;
    if (!me.profile.locationSharingEnabled) {
      _lastSentAt = null;
      state = null;
      return;
    }
    if (!_hasLocationPermission(me)) {
      _lastSentAt = null;
      state = null;
      return;
    }

    final source = ref.read(locationSourceProvider);
    final authz = await source.checkAuthorization();
    if (authz != LocationAuthorization.whileInUse &&
        authz != LocationAuthorization.always) {
      _lastSentAt = null;
      state = null;
      return;
    }
    if (_disposed) return;

    _posSub = source
        .watchPosition(
          accuracy: LocationAccuracyTier.high,
          distanceFilterMeters: 10,
        )
        .listen(
          _onPositionFix,
          onError: (Object e, StackTrace st) =>
              debugPrint('[LocationPublish] position stream error: $e $st'),
        );

    _heartbeat = Timer.periodic(heartbeatInterval, (_) => _heartbeatTick());
    unawaited(_seedCurrentPosition(source));
  }

  void _cancelHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// One-shot fix so a stationary user still publishes after subscribe (the
  /// OS stream may not emit until movement exceeds [distanceFilterMeters]).
  Future<void> _seedCurrentPosition(LocationSource source) async {
    if (_disposed || !_foreground) return;
    if (ref.read(authStateProvider).valueOrNull == null) return;
    final snap = ref.read(meNotifierProvider).valueOrNull;
    if (snap == null) return;
    final me = snap.me;
    if (!me.profile.locationSharingEnabled) return;
    if (!_hasLocationPermission(me)) return;
    try {
      final fix = await source.getCurrentPosition(
        accuracy: LocationAccuracyTier.high,
      );
      if (_disposed || !_foreground) return;
      if (ref.read(authStateProvider).valueOrNull == null) return;
      final snapAfter = ref.read(meNotifierProvider).valueOrNull;
      if (snapAfter == null) return;
      final meAfter = snapAfter.me;
      if (!meAfter.profile.locationSharingEnabled) return;
      if (!_hasLocationPermission(meAfter)) return;
      _applyFix(fix);
    } catch (e) {
      debugPrint('[LocationPublish] seed position failed: $e');
    }
  }

  void _heartbeatTick() {
    if (_disposed || !_foreground) return;
    if (ref.read(authStateProvider).valueOrNull == null) return;
    final snap = ref.read(meNotifierProvider).valueOrNull;
    if (snap == null) return;
    final me = snap.me;
    if (!me.profile.locationSharingEnabled) return;
    if (!_hasLocationPermission(me)) return;

    final fix = state;
    if (fix == null) return;
    _tryPostThrottled(fix);
  }

  static bool _hasLocationPermission(MeResponse me) {
    return me.hasPermission('woleh.place.watch') ||
        me.hasPermission('woleh.place.broadcast');
  }

  void _onPositionFix(LocationFix fix) {
    if (_disposed || !_foreground) return;
    if (ref.read(authStateProvider).valueOrNull == null) return;

    final snap = ref.read(meNotifierProvider).valueOrNull;
    if (snap == null) return;
    final me = snap.me;
    if (!me.profile.locationSharingEnabled) return;
    if (!_hasLocationPermission(me)) return;

    _applyFix(fix);
  }

  void _applyFix(LocationFix fix) {
    state = fix;
    _tryPostThrottled(fix);
  }

  void _tryPostThrottled(LocationFix fix) {
    final now = DateTime.now();
    if (_lastSentAt != null &&
        now.difference(_lastSentAt!) < minPostInterval) {
      return;
    }
    _lastSentAt = now;
    unawaited(_postFix(fix));
  }

  Future<void> _postFix(LocationFix fix) async {
    if (_disposed) return;
    try {
      await ref.read(meRepositoryProvider).postLocation(
            latitude: fix.latitude,
            longitude: fix.longitude,
            accuracyMeters: fix.accuracyMeters,
            heading: fix.headingDegrees,
            speed: fix.speedMetersPerSecond,
            recordedAt: fix.recordedAt,
          );
    } catch (e, st) {
      debugPrint('[LocationPublish] post failed: $e $st');
    }
  }

  void _stopPositionStream({required bool resetThrottle}) {
    _cancelHeartbeat();
    _posSub?.cancel();
    _posSub = null;
    if (resetThrottle) {
      _lastSentAt = null;
      state = null;
    }
  }
}

final class _AppLifecycleBinding with WidgetsBindingObserver {
  _AppLifecycleBinding(this._onChanged);

  final ValueChanged<AppLifecycleState> _onChanged;

  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _onChanged(state);
}
