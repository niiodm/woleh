import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth_state.dart';

/// Stub auth screen for Phase 0 step 4.1.
///
/// Real phone-entry form and OTP flow are built in step 4.2.
/// The "Dev: set fake token" button is the done-criterion for this step:
/// pressing it stores a token → router redirect fires → HomeScreen appears.
class PhoneScreen extends ConsumerWidget {
  const PhoneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Enter your phone number',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () =>
                  ref.read(authStateProvider.notifier).setToken('fake-dev-token'),
              child: const Text('Dev: set fake token'),
            ),
          ],
        ),
      ),
    );
  }
}
