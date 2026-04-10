import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs before [AuthState.signOut] clears tokens (e.g. unregister FCM device token).
final pushBeforeSignOutProvider = Provider<Future<void> Function(Ref)>(
  (ref) => (_) async {},
);
