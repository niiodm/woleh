import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_token_storage.g.dart';

const _kTokenKey = 'access_token';

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

  Future<String?> read() => _storage.read(key: _kTokenKey);

  Future<void> write(String token) => _storage.write(key: _kTokenKey, value: token);

  Future<void> delete() => _storage.delete(key: _kTokenKey);
}
