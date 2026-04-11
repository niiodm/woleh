import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'core/app_colors.dart';
import 'core/push_bootstrap.dart';
import 'core/push_hook.dart';
import 'core/shared_preferences_provider.dart';
import 'core/ws_client.dart';
import 'features/location/presentation/location_publish_notifier.dart';
import 'features/location/presentation/peer_locations_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        pushBeforeSignOutProvider.overrideWith(
          (ref) => unregisterPushDevices,
        ),
      ],
      child: PushBootstrap(
        child: const WolehApp(),
      ),
    ),
  );
}

class WolehApp extends ConsumerWidget {
  const WolehApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Eagerly initialise the WS client so it connects as soon as a valid
    // token is available.  keepAlive: true ensures it is never auto-disposed.
    ref.watch(wsClientProvider);
    // Phase 4: subscribe to peer_location / peer_location_revoked for the map.
    ref.watch(peerLocationsNotifierProvider);
    // Phase 4: foreground GPS → throttled POST /me/location when sharing on.
    ref.watch(locationPublishNotifierProvider);
    return MaterialApp.router(
      title: 'Woleh',
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.background,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
      ),
      routerConfig: router,
    );
  }
}
