import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dio/dio.dart';

import '../../../core/analytics.dart';
import '../../../core/analytics_provider.dart';
import '../../../core/telemetry_consent.dart';
import '../../../core/telemetry_consent_provider.dart';
import '../../../core/app_error.dart';
import '../../../core/auth_state.dart';
import '../../../shared/offline_read_only_hint.dart';
import '../../../shared/permission_gated_button.dart';
import '../../subscription/presentation/subscription_status_card.dart';
import '../data/me_dto.dart';
import '../data/me_repository.dart';
import 'me_notifier.dart';

/// Account hub: entitlements, subscription, place-list shortcuts, sign out.
///
/// WebSocket status lives on [MapHomeScreen]; matches surface as map toasts.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meAsync = ref.watch(meNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Plans',
            icon: const Icon(Icons.workspace_premium_outlined),
            onPressed: () {
              unawaited(
                ref.read(wolehAnalyticsProvider).logButtonTapped(
                      'open_plans',
                      screenName: '/profile',
                    ),
              );
              context.push('/plans');
            },
          ),
          IconButton(
            tooltip: 'Edit profile',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              unawaited(
                ref.read(wolehAnalyticsProvider).logButtonTapped(
                      'edit_profile',
                      screenName: '/profile',
                    ),
              );
              context.push('/me/edit');
            },
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () {
              unawaited(
                ref.read(wolehAnalyticsProvider).logButtonTapped(
                      'sign_out',
                      screenName: '/profile',
                    ),
              );
              ref.read(authStateProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: meAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err is OfflineError ? err.message : err.toString(),
          onRetry: () => ref.read(meNotifierProvider.notifier).refresh(),
        ),
        data: (snapshot) {
          if (snapshot == null) return const SizedBox.shrink();
          return _ProfileBody(me: snapshot.me, fromCache: snapshot.fromCache);
        },
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.me, required this.fromCache});

  final MeResponse me;
  final bool fromCache;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async {
        final container = ProviderScope.containerOf(context);
        await container.read(meNotifierProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        children: [
          if (fromCache)
            const Align(
              alignment: Alignment.center,
              child: ShowingSavedDataChip(),
            ),
          Center(
            child: Column(
              children: [
                _Avatar(displayName: me.profile.displayNameOrPhone),
                const SizedBox(height: 16),
                Text(
                  me.profile.displayNameOrPhone,
                  style: textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  me.profile.phoneE164,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _TierChip(tier: me.tier),
                const SizedBox(height: 8),
                SubscriptionStatusCard(me: me),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text('Permissions', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          if (me.permissions.isEmpty)
            Text('None', style: textTheme.bodyMedium)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: me.permissions
                  .map((p) => _PermissionChip(permission: p))
                  .toList(),
            ),
          const SizedBox(height: 24),
          Text('Limits', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          _LimitRow(
            icon: Icons.visibility_outlined,
            label: 'Watch places',
            value: me.limits.placeWatchMax,
          ),
          _LimitRow(
            icon: Icons.radio_outlined,
            label: 'Broadcast places',
            value: me.limits.placeBroadcastMax,
          ),
          _LimitRow(
            icon: Icons.bookmarks_outlined,
            label: 'Saved place lists',
            value: me.limits.savedPlaceListMax,
          ),
          if (me.permissions.contains('woleh.place.watch') ||
              me.permissions.contains('woleh.place.broadcast')) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text('Map & location', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            _LocationSharingTile(me: me),
          ],
          if (kFirebaseAnalyticsEnabled) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text('Privacy', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            const _PrivacyAnalyticsTile(),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text('Actions', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          PermissionGatedButton(
            icon: Icons.visibility_outlined,
            label: 'My Watch List',
            hasPermission: me.permissions.contains('woleh.place.watch'),
            onTap: () => context.push('/watch'),
            onLockedTap: () => context.push('/plans'),
          ),
          const SizedBox(height: 8),
          PermissionGatedButton(
            icon: Icons.radio_outlined,
            label: 'Broadcast your route',
            hasPermission: me.permissions.contains('woleh.place.broadcast'),
            onTap: () => context.push('/broadcast'),
            onLockedTap: () => context.push('/plans'),
          ),
          const SizedBox(height: 8),
          PermissionGatedButton(
            icon: Icons.map_outlined,
            label: 'Map home',
            hasPermission:
                me.permissions.contains('woleh.place.watch') ||
                me.permissions.contains('woleh.place.broadcast'),
            onTap: () => context.go('/home'),
            onLockedTap: () => context.push('/plans'),
          ),
          const SizedBox(height: 8),
          PermissionGatedButton(
            icon: Icons.bookmarks_outlined,
            label: 'Saved lists',
            hasPermission:
                me.permissions.contains('woleh.place.watch') ||
                me.permissions.contains('woleh.place.broadcast'),
            onTap: () => context.push('/saved-lists'),
            onLockedTap: () => context.push('/plans'),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    final initials = displayName.trim().isNotEmpty
        ? displayName.trim()[0].toUpperCase()
        : '?';
    return CircleAvatar(
      radius: 40,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        initials,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _PrivacyAnalyticsTile extends ConsumerWidget {
  const _PrivacyAnalyticsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kSkipTelemetryConsentPrompt) {
      return Text(
        'Product analytics is controlled by the build (WOLEH_SKIP_TELEMETRY_CONSENT).',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    final firebaseUp = Firebase.apps.isNotEmpty;
    if (!firebaseUp) {
      return Text(
        'Product analytics: enable Firebase (e.g. push, monitoring, or analytics) to change this.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    final consent = ref.watch(telemetryConsentProvider);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Product analytics'),
      subtitle: const Text(
        'Anonymous usage and screen views. Crash reporting follows '
        'WOLEH_FIREBASE_MONITORING — see mobile README.',
      ),
           value: consent == true,
      onChanged: (v) async {
        await ref
            .read(telemetryConsentProvider.notifier)
            .setProductAnalyticsAllowed(v);
        try {
          await ref.read(meRepositoryProvider).patchProfile(
                productAnalyticsConsent: v,
              );
          await ref.read(meNotifierProvider.notifier).refresh();
        } catch (_) {
          await ref.read(meNotifierProvider.notifier).refresh();
        }
      },
    );
  }
}

class _LocationSharingTile extends ConsumerStatefulWidget {
  const _LocationSharingTile({required this.me});

  final MeResponse me;

  @override
  ConsumerState<_LocationSharingTile> createState() =>
      _LocationSharingTileState();
}

class _LocationSharingTileState extends ConsumerState<_LocationSharingTile> {
  bool _busy = false;

  Future<void> _onChanged(bool value) async {
    setState(() => _busy = true);
    try {
      await ref.read(meRepositoryProvider).putLocationSharing(enabled: value);
      await ref.read(meNotifierProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      final err = e is DioException && e.error is AppError
          ? e.error as AppError
          : UnknownError(e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.me.profile.locationSharingEnabled;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Share location with matches'),
      subtitle: Text(
        'When on, matched peers can see your position on the map. '
        'Requires watch or broadcast access.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      value: enabled,
      onChanged: _busy ? null : _onChanged,
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({required this.tier});

  final String tier;

  @override
  Widget build(BuildContext context) {
    final isPaid = tier == 'paid';
    final colors = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        isPaid ? Icons.star_rounded : Icons.person_outline,
        size: 16,
        color: isPaid ? colors.secondary : colors.onSurfaceVariant,
      ),
      label: Text(isPaid ? 'Pro' : 'Free'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({required this.permission});

  final String permission;

  static const _labels = {
    'woleh.account.profile': 'Profile',
    'woleh.plans.read': 'Plans',
    'woleh.place.watch': 'Watch',
    'woleh.place.broadcast': 'Broadcast',
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[permission] ?? permission.split('.').last;
    return Chip(label: Text(label), visualDensity: VisualDensity.compact);
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            value == 0 ? 'Not available' : '$value',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: value == 0
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load profile',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
