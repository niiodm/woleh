import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/analytics_provider.dart';
import '../data/saved_list_share_url.dart';

/// Scans a QR code and opens import for a saved-list share token.
class SavedListScanScreen extends ConsumerStatefulWidget {
  const SavedListScanScreen({super.key});

  @override
  ConsumerState<SavedListScanScreen> createState() =>
      _SavedListScanScreenState();
}

class _SavedListScanScreenState extends ConsumerState<SavedListScanScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      final token = parseSavedListShareToken(raw);
      if (token == null || token.isEmpty) continue;
      _handled = true;
      unawaited(
        ref.read(wolehAnalyticsProvider).logButtonTapped(
              'saved_list_scan_success',
              screenName: '/saved-lists/scan',
            ),
      );
      if (!mounted) return;
      final importRoute = context.push<String?>(
        '/saved-lists/import?token=${Uri.encodeQueryComponent(token)}',
      );
      unawaited(
        importRoute.then((_) {
          if (mounted) setState(() => _handled = false);
        }),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan list QR'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Point the camera at a Woleh saved-list QR code.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                        shadows: const [
                          Shadow(blurRadius: 8, color: Colors.black87),
                        ],
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
