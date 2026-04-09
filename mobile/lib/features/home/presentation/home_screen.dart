import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth_state.dart';
import '../../../shared/permission_gated_button.dart';
import '../../me/data/me_dto.dart';
import '../../me/presentation/me_notifier.dart';
import '../../subscription/presentation/subscription_status_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meAsync = ref.watch(meNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Woleh'),
        actions: [
          IconButton(
            tooltip: 'Plans',
            icon: const Icon(Icons.workspace_premium_outlined),
            onPressed: () => context.push('/plans'),
          ),
          IconButton(
            tooltip: 'Edit profile',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/me/edit'),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authStateProvider.notifier).signOut(),
          ),
        ],
      ),
      body: meAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err.toString(),
          onRetry: () => ref.read(meNotifierProvider.notifier).refresh(),
        ),
        data: (me) {
          if (me == null) return const SizedBox.shrink();
          return _MeView(me: me);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile + entitlements view
// ---------------------------------------------------------------------------

class _MeView extends StatelessWidget {
  const _MeView({required this.me});

  final MeResponse me;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async {
        // Exposed via the notifier; pull-to-refresh re-fetches GET /me.
        final container = ProviderScope.containerOf(context);
        await container.read(meNotifierProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        children: [
          // Avatar + name + phone
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
                  style: textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
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

          // Permissions
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

          // Limits
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

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // Actions
          Text('Actions', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          PermissionGatedButton(
            icon: Icons.radio_outlined,
            label: 'Broadcast your route',
            hasPermission:
                me.permissions.contains('woleh.place.broadcast'),
            onTap: () => context.push('/broadcast'),
            onLockedTap: () => context.push('/plans'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

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
        color: isPaid ? Colors.amber : colors.onSurfaceVariant,
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
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
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
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
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

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

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
            Icon(Icons.cloud_off_outlined,
                size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
