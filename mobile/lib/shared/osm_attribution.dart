import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// OpenStreetMap copyright page (ODbL / attribution requirements).
const osmCopyrightPageUrl = 'https://www.openstreetmap.org/copyright';

Future<void> openOsmCopyrightPage() {
  return launchUrl(
    Uri.parse(osmCopyrightPageUrl),
    mode: LaunchMode.externalApplication,
  );
}

/// Compact, tappable “© OpenStreetMap contributors” line for non-map screens.
class OsmAttributionFooter extends StatelessWidget {
  const OsmAttributionFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.9);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: color,
      decoration: TextDecoration.underline,
      decorationColor: color.withValues(alpha: 0.45),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: openOsmCopyrightPage,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                '© OpenStreetMap contributors',
                style: style,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
