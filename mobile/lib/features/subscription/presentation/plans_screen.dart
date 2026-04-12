import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics_provider.dart';
import '../../me/presentation/me_notifier.dart';
import '../data/plans_dto.dart';
import 'plans_notifier.dart';

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(plansNotifierProvider);
    final meAsync = ref.watch(meNotifierProvider);
    final currentTier = meAsync.valueOrNull?.me.tier ?? 'free';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plans'),
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(plansNotifierProvider),
        ),
        data: (plans) => _PlansBody(plans: plans, currentTier: currentTier),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _PlansBody extends StatelessWidget {
  const _PlansBody({required this.plans, required this.currentTier});

  final List<PlanDto> plans;
  final String currentTier;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        Text(
          'Choose your plan',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Upgrade any time to unlock all features.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        ...plans.map(
          (plan) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _PlanCard(
              plan: plan,
              isCurrent: _isCurrentPlan(plan, currentTier),
            ),
          ),
        ),
      ],
    );
  }

  bool _isCurrentPlan(PlanDto plan, String tier) {
    if (tier == 'paid') return !plan.isFree;
    return plan.isFree;
  }
}

// ---------------------------------------------------------------------------
// Plan card
// ---------------------------------------------------------------------------

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.isCurrent});

  final PlanDto plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      elevation: isCurrent ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isCurrent
            ? BorderSide(color: colors.primary, width: 2)
            : BorderSide.none,
      ),
      color: isCurrent ? colors.primaryContainer.withAlpha(60) : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PlanHeader(plan: plan, isCurrent: isCurrent),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _PermissionList(permissions: plan.permissionsGranted),
            const SizedBox(height: 12),
            _LimitsRow(limits: plan.limits),
            const SizedBox(height: 20),
            _PlanCta(plan: plan, isCurrent: isCurrent),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card sub-widgets
// ---------------------------------------------------------------------------

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.plan, required this.isCurrent});

  final PlanDto plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(
          plan.isFree ? Icons.person_outline : Icons.star_rounded,
          color: plan.isFree ? colors.onSurfaceVariant : colors.secondary,
          size: 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(plan.displayName, style: textTheme.titleLarge),
                  if (isCurrent) ...[
                    const SizedBox(width: 8),
                    Chip(
                      label: const Text('Current plan'),
                      padding: EdgeInsets.zero,
                      labelStyle: textTheme.labelSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                      backgroundColor: colors.primaryContainer,
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _formatPrice(plan.price),
                style: textTheme.headlineMedium?.copyWith(
                  color: plan.isFree ? colors.onSurfaceVariant : colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatPrice(PlanPrice price) {
    if (price.amountMinor == 0) return 'Free';
    final ghs = price.amountMinor / 100;
    return '${price.currency} ${ghs.toStringAsFixed(2)} / month';
  }
}

class _PermissionList extends StatelessWidget {
  const _PermissionList({required this.permissions});

  final List<String> permissions;

  static const _labels = <String, String>{
    'woleh.account.profile': 'Manage profile',
    'woleh.plans.read': 'View plans',
    'woleh.place.watch': 'Watch places',
    'woleh.place.broadcast': 'Broadcast your route',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: permissions.map((p) {
        final label = _labels[p] ?? p.split('.').last;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text(label,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _LimitsRow extends StatelessWidget {
  const _LimitsRow({required this.limits});

  final PlanLimits limits;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        );
    return Row(
      children: [
        Icon(Icons.visibility_outlined,
            size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text('Watch up to ${limits.placeWatchMax}', style: style),
        const SizedBox(width: 16),
        Icon(Icons.radio_outlined, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          limits.placeBroadcastMax == 0
              ? 'No broadcasting'
              : 'Broadcast up to ${limits.placeBroadcastMax}',
          style: style,
        ),
      ],
    );
  }
}

class _PlanCta extends ConsumerWidget {
  const _PlanCta({required this.plan, required this.isCurrent});

  final PlanDto plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isCurrent) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: null,
          child: const Text('Current plan'),
        ),
      );
    }
    if (plan.isFree) {
      // Free plan — user is on paid tier; show a downgrade hint (no action).
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: null,
          child: const Text('Free plan'),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () {
          unawaited(
            ref.read(wolehAnalyticsProvider).logEvent(
                  'subscription_checkout_started',
                  {'plan_id': plan.planId},
                ),
          );
          context.push('/checkout/${plan.planId}');
        },
        child: const Text('Subscribe'),
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
                size: 56,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Could not load plans',
                style: Theme.of(context).textTheme.titleMedium),
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
