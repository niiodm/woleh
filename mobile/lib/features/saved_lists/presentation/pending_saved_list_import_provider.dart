import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When a share link opens the app before sign-in, the token is held here until
/// [authStateProvider] becomes non-null, then the app navigates to import.
final pendingSavedListImportTokenProvider =
    StateProvider<String?>((ref) => null);
