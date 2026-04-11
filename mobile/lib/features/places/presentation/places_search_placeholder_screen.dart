import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Temporary route until places search (plan step 4) ships.
class PlacesSearchPlaceholderScreen extends StatelessWidget {
  const PlacesSearchPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search places'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Place search and list editing will be available in a follow-up.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
