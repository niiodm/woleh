import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/analytics_provider.dart';
import '../../../core/app_error.dart';
import '../../me/data/me_repository.dart';
import '../../me/presentation/me_notifier.dart';

part 'setup_name_screen.g.dart';

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

enum SetupNameStatus { idle, saving, error }

class SetupNameState {
  const SetupNameState({
    this.status = SetupNameStatus.idle,
    this.errorMessage,
  });

  final SetupNameStatus status;
  final String? errorMessage;

  bool get isLoading => status == SetupNameStatus.saving;
}

@riverpod
class SetupNameNotifier extends _$SetupNameNotifier {
  @override
  SetupNameState build() => const SetupNameState();

  /// Saves [displayName] via `PATCH /me/profile`. Returns true on success.
  Future<bool> save(String displayName) async {
    state = const SetupNameState(status: SetupNameStatus.saving);
    try {
      await ref.read(meRepositoryProvider).patchDisplayName(displayName);
      await ref.read(meNotifierProvider.notifier).refresh();
      state = const SetupNameState();
      return true;
    } catch (e) {
      final err = e is DioException && e.error is AppError
          ? e.error as AppError
          : UnknownError(e.toString());
      state = SetupNameState(
        status: SetupNameStatus.error,
        errorMessage: err.message,
      );
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SetupNameScreen extends ConsumerStatefulWidget {
  const SetupNameScreen({super.key});

  @override
  ConsumerState<SetupNameScreen> createState() => _SetupNameScreenState();
}

class _SetupNameScreenState extends ConsumerState<SetupNameScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    unawaited(
      ref.read(wolehAnalyticsProvider).logButtonTapped(
            'save_and_continue',
            screenName: '/auth/setup-name',
          ),
    );
    final name = _controller.text.trim();
    if (name.isEmpty) {
      unawaited(
        ref.read(wolehAnalyticsProvider).logEvent('setup_name_completed', {
          'action': 'continue_empty',
        }),
      );
      _continueToHome();
      return;
    }
    final ok = await ref.read(setupNameNotifierProvider.notifier).save(name);
    if (ok && mounted) {
      unawaited(
        ref.read(wolehAnalyticsProvider).logEvent('setup_name_completed', {
          'action': 'save',
        }),
      );
      _continueToHome();
    }
  }

  void _skip() {
    unawaited(
      ref.read(wolehAnalyticsProvider).logButtonTapped(
            'skip_setup_name',
            screenName: '/auth/setup-name',
          ),
    );
    unawaited(
      ref.read(wolehAnalyticsProvider).logEvent('setup_name_completed', {
        'action': 'skip',
      }),
    );
    _continueToHome();
  }

  void _continueToHome() => context.go('/home');

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setupNameNotifierProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.waving_hand_rounded, size: 56),
              const SizedBox(height: 24),
              Text(
                'Welcome to Woleh!',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'What should we call you? You can always change this later.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  hintText: 'e.g. Ama',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              if (state.status == SetupNameStatus.error &&
                  state.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _ErrorBanner(state.errorMessage!),
                ),
              FilledButton(
                onPressed: state.isLoading ? null : _save,
                child: state.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save & continue'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: state.isLoading ? null : _skip,
                child: const Text('Skip for now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
