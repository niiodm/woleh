import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'live_map_stack.dart';

/// Live map with a back button — same layer as map home, embedded layout.
///
/// Prefer navigating to `/home`; `/map` redirects there.
class LiveMapScreen extends ConsumerWidget {
  const LiveMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live map'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: const LiveMapStack(forMapHome: false),
    );
  }
}
