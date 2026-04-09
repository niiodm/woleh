import 'package:flutter/material.dart';

/// Placeholder for the Broadcast screen — real implementation in Phase 2.
///
/// Gated behind [woleh.place.broadcast]; the router redirects users who lack
/// this permission to the Plans screen before they ever reach this screen.
class BroadcastPlaceholderScreen extends StatelessWidget {
  const BroadcastPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Broadcast')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.radio_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Broadcast coming in Phase 2',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
