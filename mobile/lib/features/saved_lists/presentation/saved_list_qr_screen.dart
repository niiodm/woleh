import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/saved_list_share_url.dart';

/// Full-screen QR for sharing a saved list deep link.
class SavedListQrScreen extends StatelessWidget {
  const SavedListQrScreen({
    super.key,
    required this.title,
    required this.shareToken,
  });

  final String title;
  final String shareToken;

  @override
  Widget build(BuildContext context) {
    final link = savedListShareDeepLink(shareToken);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Share list')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: QrImageView(
                    data: link,
                    version: QrVersions.auto,
                    backgroundColor: scheme.surface,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: scheme.onSurface,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              SelectableText(
                link,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy link'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
