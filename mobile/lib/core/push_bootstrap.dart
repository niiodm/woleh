import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/me/data/me_dto.dart';
import '../features/me/data/me_repository.dart';
import '../features/me/presentation/me_notifier.dart';
import 'shared_preferences_provider.dart';

/// Compile-time flag — default off until FCM credentials are configured.
///
/// Enable locally with:
/// `flutter run --dart-define=WOLEH_PUSH_ENABLED=true`
const kPushEnabled = bool.fromEnvironment(
  'WOLEH_PUSH_ENABLED',
  defaultValue: false,
);

const _kPrefPermissionAsked = 'push.permission_prompted';
const _kPrefLastToken = 'push.last_registered_token';

/// Root [ScaffoldMessenger] for foreground FCM [SnackBar]s.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> unregisterPushDevices(Ref ref) async {
  if (!kPushEnabled) return;
  final prefs = ref.read(sharedPreferencesProvider);
  final token = prefs.getString(_kPrefLastToken);
  if (token == null || token.isEmpty) return;
  try {
    await ref.read(meRepositoryProvider).deleteDeviceToken(token);
  } catch (_) {
    // Best-effort — user is signing out regardless.
  }
  await prefs.remove(_kPrefLastToken);
}

/// Wraps the app: initializes Firebase when [kPushEnabled], registers for push
/// after profile load, and shows foreground notifications.
class PushBootstrap extends ConsumerStatefulWidget {
  const PushBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushBootstrap> createState() => _PushBootstrapState();
}

class _PushBootstrapState extends ConsumerState<PushBootstrap> {
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _firebaseReady = false;

  @override
  void initState() {
    super.initState();
    if (kPushEnabled) {
      unawaited(_initFirebase());
    }
  }

  Future<void> _initFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      if (!mounted) return;
      _firebaseReady = true;
      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      _tokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);
      setState(() {});
      final me = ref.read(meNotifierProvider);
      me.whenData((snapshot) {
        unawaited(_maybeRegisterAfterProfile(snapshot));
      });
    } catch (e, st) {
      debugPrint('PushBootstrap: Firebase.initializeApp failed: $e\n$st');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final body = message.notification?.body ??
        message.notification?.title ??
        message.data['body'] ??
        '';
    if (body.isEmpty) return;
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(body),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onTokenRefresh(String token) async {
    if (!mounted || !_firebaseReady) return;
    await _registerToken(token);
  }

  Future<void> _maybeRegisterAfterProfile(MeLoadSnapshot? snapshot) async {
    if (!kPushEnabled || !_firebaseReady || snapshot == null) return;

    final prefs = ref.read(sharedPreferencesProvider);
    final asked = prefs.getBool(_kPrefPermissionAsked) ?? false;

    if (!asked) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await prefs.setBool(_kPrefPermissionAsked, true);
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
    } else {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _registerToken(token);
    }
  }

  Future<void> _registerToken(String token) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final platform = Platform.isIOS ? 'ios' : 'android';
    try {
      await ref.read(meRepositoryProvider).registerDeviceToken(
            token: token,
            platform: platform,
          );
      await prefs.setString(_kPrefLastToken, token);
    } catch (e) {
      debugPrint('PushBootstrap: registerDeviceToken failed: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_foregroundSub?.cancel());
    unawaited(_tokenRefreshSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kPushEnabled) {
      ref.listen<AsyncValue<MeLoadSnapshot?>>(meNotifierProvider, (prev, next) {
        next.whenData((snapshot) {
          unawaited(_maybeRegisterAfterProfile(snapshot));
        });
      });
    }
    return widget.child;
  }
}
