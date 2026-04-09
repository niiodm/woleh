import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../me/data/me_dto.dart';

/// Surfaces the current subscription state below the tier chip on the home
/// screen.  Three distinct presentations:
///
///  - **Paid / active** — compact "Renews D Mon YYYY" row.
///  - **Grace period** — prominent warning banner with days remaining and a
///    CTA to the Plans screen.
///  - **Free** — single-line "Free plan · Upgrade →" link row.
class SubscriptionStatusCard extends StatelessWidget {
  const SubscriptionStatusCard({super.key, required this.me});

  final MeResponse me;

  @override
  Widget build(BuildContext context) {
    final sub = me.subscription;

    if (sub.inGracePeriod && sub.currentPeriodEnd != null) {
      return _GracePeriodBanner(currentPeriodEnd: sub.currentPeriodEnd!);
    }
    if (me.tier == 'paid' && sub.currentPeriodEnd != null) {
      return _PaidStatusRow(currentPeriodEnd: sub.currentPeriodEnd!);
    }
    return const _FreeStatusRow();
  }
}

// ---------------------------------------------------------------------------
// Paid — active
// ---------------------------------------------------------------------------

class _PaidStatusRow extends StatelessWidget {
  const _PaidStatusRow({required this.currentPeriodEnd});

  final String currentPeriodEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.autorenew, size: 14, color: colors.primary),
        const SizedBox(width: 4),
        Text(
          'Renews ${_formatDate(currentPeriodEnd)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.primary,
              ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Grace period — warning banner
// ---------------------------------------------------------------------------

class _GracePeriodBanner extends StatelessWidget {
  const _GracePeriodBanner({required this.currentPeriodEnd});

  final String currentPeriodEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final daysRemaining = _graceDaysRemaining(currentPeriodEnd);

    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: colors.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your subscription has expired',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colors.onErrorContainer,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              daysRemaining > 0
                  ? 'You have $daysRemaining day${daysRemaining == 1 ? '' : 's'} of access remaining.'
                  : 'Your grace period has ended.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onErrorContainer,
                  ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                ),
                onPressed: () => context.push('/plans'),
                child: const Text('View plans'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Free — upgrade prompt
// ---------------------------------------------------------------------------

class _FreeStatusRow extends StatelessWidget {
  const _FreeStatusRow();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.push('/plans'),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Free plan · ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          Text(
            'Upgrade →',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Formats an ISO-8601 UTC string as "D Mon YYYY", e.g. "7 May 2026".
String _formatDate(String isoDate) {
  final dt = DateTime.parse(isoDate).toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

/// Returns the number of whole days remaining in the 7-day grace period.
/// Grace period end = currentPeriodEnd + 7 days.
int _graceDaysRemaining(String currentPeriodEnd) {
  final periodEnd = DateTime.parse(currentPeriodEnd).toUtc();
  final gracePeriodEnd = periodEnd.add(const Duration(days: 7));
  final remaining = gracePeriodEnd.difference(DateTime.now().toUtc());
  return remaining.inDays.clamp(0, 7);
}
