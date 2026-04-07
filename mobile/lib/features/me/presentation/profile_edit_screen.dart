import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/app_error.dart';
import '../data/me_repository.dart';
import 'me_notifier.dart';

part 'profile_edit_screen.g.dart';

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

enum ProfileEditStatus { idle, saving, error }

class ProfileEditState {
  const ProfileEditState({
    this.status = ProfileEditStatus.idle,
    this.errorMessage,
  });

  final ProfileEditStatus status;
  final String? errorMessage;

  bool get isSaving => status == ProfileEditStatus.saving;
}

@riverpod
class ProfileEditNotifier extends _$ProfileEditNotifier {
  @override
  ProfileEditState build() => const ProfileEditState();

  /// Calls `PATCH /me/profile`, then refreshes `meNotifierProvider`.
  /// Returns `true` on success so the screen can pop.
  Future<bool> save(String displayName) async {
    state = const ProfileEditState(status: ProfileEditStatus.saving);
    try {
      await ref.read(meRepositoryProvider).patchDisplayName(displayName.trim());
      // Refresh the cached me data so HomeScreen reflects the new name.
      await ref.read(meNotifierProvider.notifier).refresh();
      state = const ProfileEditState();
      return true;
    } catch (e) {
      final err = e is DioException && e.error is AppError
          ? e.error as AppError
          : UnknownError(e.toString());
      state = ProfileEditState(
        status: ProfileEditStatus.error,
        errorMessage: err.message,
      );
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _controller = TextEditingController();
  bool _initialised = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Pre-fill the field with the current display name the first time
  /// the me data is available (may arrive slightly after build).
  void _maybeInit(String? currentName) {
    if (_initialised) return;
    _initialised = true;
    _controller.text = currentName ?? '';
    // Position cursor at end.
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  Future<void> _save() async {
    final ok = await ref
        .read(profileEditNotifierProvider.notifier)
        .save(_controller.text);
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final editState = ref.watch(profileEditNotifierProvider);
    final meAsync = ref.watch(meNotifierProvider);

    // Pre-fill once me data arrives.
    meAsync.whenData((me) => _maybeInit(me?.profile.displayName));

    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: editState.isSaving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  hintText: 'e.g. Ama',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              if (editState.status == ProfileEditStatus.error &&
                  editState.errorMessage != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: colors.onErrorContainer, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          editState.errorMessage!,
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: editState.isSaving ? null : _save,
                child: editState.isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
