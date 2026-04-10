import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth_state.dart';
import '../../../core/ws_message.dart';
import '../../../shared/permission_gated_button.dart';
import '../../../core/app_error.dart';
import '../../../shared/offline_read_only_hint.dart';
import '../../../shared/ws_status_banner.dart';
import '../../me/data/me_dto.dart';
import '../../me/presentation/me_notifier.dart';
import '../../places/presentation/match_notifier.dart';
import '../../subscription/presentation/subscription_status_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meAsync = ref.watch(meNotifierProvider);
    // Always watch so the notifier is alive and captures events while the
    // user is on this screen.
    final matches = ref.watch(matchNotifierProvider);

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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WsStatusBanner(),
          Expanded(
            child: meAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => _ErrorView(
                message: err is OfflineError ? err.message : err.toString(),
                onRetry: () =>
                    ref.read(meNotifierProvider.notifier).refresh(),
              ),
              data: (snapshot) {
                if (snapshot == null) return const SizedBox.shrink();
                return _MeView(
                  me: snapshot.me,
                  fromCache: snapshot.fromCache,
                  matches: matches,
                  onDismiss: (i) =>
                      ref.read(matchNotifierProvider.notifier).dismiss(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile + entitlements view
// ---------------------------------------------------------------------------

class _MeView extends StatelessWidget {
  const _MeView({
    required this.me,
    required this.fromCache,
    required this.matches,
    required this.onDismiss,
  });

  final MeResponse me;
  final bool fromCache;
  final List<MatchMessage> matches;
  final void Function(int index) onDismiss;

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
          if (fromCache)
            const Align(
              alignment: Alignment.center,
              child: ShowingSavedDataChip(),
            ),
          // ── Match banner (shown when recent matches are available) ─────────
          if (matches.isNotEmpty) ...[
            Text('Recent Matches', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            ...List.generate(matches.length, (i) {
              final match = matches[i];
              return _MatchCard(
                match: match,
                onDismiss: () => onDismiss(i),
                onTap: () {
                  onDismiss(i);
                  context.push('/watch');
                },
              );
            }),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
          ],

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
            hasPermission:
                me.permissions.contains('woleh.place.broadcast'),
            onTap: () => context.push('/broadcast'),
            onLockedTap: () => context.push('/plans'),
          ),
          const SizedBox(height: 8),
          PermissionGatedButton(
            icon: Icons.map_outlined,
            label: 'Live map',
            hasPermission: me.permissions.contains('woleh.place.watch') ||
                me.permissions.contains('woleh.place.broadcast'),
            onTap: () => context.push('/map'),
            onLockedTap: () => context.push('/plans'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Match card (dismissible notification tile)
// ---------------------------------------------------------------------------

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.onDismiss,
    required this.onTap,
  });

  final MatchMessage match;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final names = match.matchedNames.join(', ');
    final isWatcher = match.kind == 'watcher';
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.tertiaryContainer,
          child: Icon(
            isWatcher
                ? Icons.directions_bus_outlined
                : Icons.person_search_outlined,
            color: colors.onTertiaryContainer,
          ),
        ),
        title: Text(
          isWatcher
              ? 'A bus is heading through: $names'
              : 'A watcher needs: $names',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Tap to view your watch list',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.map_outlined, size: 20),
              tooltip: 'Live map',
              onPressed: () => context.push('/map'),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDismiss,
              tooltip: 'Dismiss',
            ),
          ],
        ),
        onTap: onTap,
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
