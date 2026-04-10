import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'shared_preferences_provider.g.dart';

/// App-wide preferences instance.
///
/// Must be overridden in `main()` after `SharedPreferences.getInstance()`.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) => throw StateError(
 'sharedPreferencesProvider must be overridden in main() '
      'with SharedPreferences.getInstance().',
    );
