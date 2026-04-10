import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_token_storage.g.dart';

const _kAccessTokenKey = 'access_token';
const _kRefreshTokenKey = 'refresh_token';

@Riverpod(keepAlive: true)
FlutterSecureStorage flutterSecureStorage(Ref ref) {
  return const FlutterSecureStorage();
}

@Riverpod(keepAlive: true)
AuthTokenStorage authTokenStorage(Ref ref) {
  return AuthTokenStorage(ref.watch(flutterSecureStorageProvider));
}

class AuthTokenStorage {
  const AuthTokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  // ── access token ────────────────────────────────────────────────────────────

  Future<String?> read() => _storage.read(key: _kAccessTokenKey);

  Future<void> write(String token) =>
      _storage.write(key: _kAccessTokenKey, value: token);

  Future<void> delete() => _storage.delete(key: _kAccessTokenKey);

  // ── refresh token ────────────────────────────────────────────────────────────

  Future<String?> readRefreshToken() =>
      _storage.read(key: _kRefreshTokenKey);

  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _kRefreshTokenKey, value: token);

  Future<void> deleteRefreshToken() =>
      _storage.delete(key: _kRefreshTokenKey);
}
