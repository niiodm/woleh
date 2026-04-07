import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_token_storage.dart';

part 'auth_state.g.dart';

/// Holds the current access token (null = unauthenticated).
///
/// Build reads from secure storage; [setToken] / [signOut] update both
/// storage and in-memory state so the router redirect fires immediately.
@Riverpod(keepAlive: true)
class AuthState extends _$AuthState {
  @override
  Future<String?> build() async {
    return ref.watch(authTokenStorageProvider).read();
  }

  Future<void> setToken(String token) async {
    await ref.read(authTokenStorageProvider).write(token);
    state = AsyncData(token);
  }

  Future<void> signOut() async {
    await ref.read(authTokenStorageProvider).delete();
    state = const AsyncData(null);
  }
}
