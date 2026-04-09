import 'package:flutter/material.dart';

/// A tappable feature entry that changes appearance based on whether the user
/// holds the required permission.
///
/// **Unlocked** (`hasPermission: true`): renders with active colours and an
/// arrow icon; tapping calls [onTap].
///
/// **Locked** (`hasPermission: false`): renders greyed-out with a padlock
/// badge overlaid on the feature icon; tapping calls [onLockedTap], which
/// should route to the Plans / upgrade screen.
///
/// Place in `mobile/lib/shared/` so any feature screen can reuse the pattern.
class PermissionGatedButton extends StatelessWidget {
  const PermissionGatedButton({
    super.key,
    required this.icon,
    required this.label,
    required this.hasPermission,
    required this.onTap,
    required this.onLockedTap,
    this.lockedMessage = 'Upgrade to unlock',
  });

  final IconData icon;
  final String label;
  final bool hasPermission;
  final VoidCallback onTap;
  final VoidCallback onLockedTap;

  /// Subtitle shown on the locked variant. Defaults to "Upgrade to unlock".
  final String lockedMessage;

  @override
  Widget build(BuildContext context) {
    return hasPermission ? _Unlocked(this) : _Locked(this);
  }
}

// ---------------------------------------------------------------------------
// Unlocked variant
// ---------------------------------------------------------------------------

class _Unlocked extends StatelessWidget {
  const _Unlocked(this.button);
  final PermissionGatedButton button;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(button.icon, color: colors.primary),
        title: Text(
          button.label,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: colors.primary),
        onTap: button.onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Locked variant
// ---------------------------------------------------------------------------

class _Locked extends StatelessWidget {
  const _Locked(this.button);
  final PermissionGatedButton button;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = colors.onSurfaceVariant.withAlpha(120);
    return Card(
      elevation: 0,
      color: colors.surfaceContainerHighest.withAlpha(80),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withAlpha(80)),
      ),
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(button.icon, color: muted),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock, size: 12, color: muted),
              ),
            ),
          ],
        ),
        title: Text(
          button.label,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: muted, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          button.lockedMessage,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.primary),
        ),
        onTap: button.onLockedTap,
      ),
    );
  }
}
