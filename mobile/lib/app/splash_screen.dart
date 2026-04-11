import 'package:flutter/material.dart';

import '../shared/osm_attribution.dart';

/// First route while auth state is loading from secure storage.
///
/// [GoRouter] redirects to `/auth/phone`, `/home`, or `/profile` once the token
/// and `GET /me` are known (map permissions choose between home and profile).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const _splashBackground = Color(0xFFF8F8F6);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: _splashBackground,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/branding/app_icon.png',
                  width: 120,
                  height: 120,
                ),
                const SizedBox(height: 16),
                Text(
                  'Woleh',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                ),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ],
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: OsmAttributionFooter(),
          ),
        ],
      ),
    );
  }
}
