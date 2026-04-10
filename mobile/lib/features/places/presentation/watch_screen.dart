import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_error.dart';
import '../../../core/place_name_normalizer.dart';
import '../../../shared/offline_read_only_hint.dart';
import '../../../core/ws_client.dart';
import '../../../core/ws_message.dart';
import 'watch_notifier.dart';

class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({super.key});

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  final _nameController = TextEditingController();
  final _fieldFocus = FocusNode();
  StreamSubscription<WsMessage>? _matchSub;

  @override
  void initState() {
    super.initState();
    _matchSub =
        ref.read(wsClientProvider.notifier).messages.listen((msg) {
      if (!mounted || msg is! MatchMessage) return;
      final names = msg.matchedNames.join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Match found — a vehicle covers $names'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    _matchSub = null;
    _nameController.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _submitAdd() {
    final text = _nameController.text;
    if (text.trim().isEmpty) return;
    ref.read(watchNotifierProvider.notifier).add(text);
    _nameController.clear();
    _fieldFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final watchState = ref.watch(watchNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch List'),
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: switch (watchState) {
        WatchLoading() => const Center(child: CircularProgressIndicator()),
        WatchLoadError(:final message) => _ErrorView(
            message: message,
            onRetry: () =>
                ref.read(watchNotifierProvider.notifier).refresh(),
          ),
        WatchReady() => _ReadyBody(
            state: watchState,
            nameController: _nameController,
            fieldFocus: _fieldFocus,
            readOnlyOffline: watchState.readOnlyOffline,
            onSubmitAdd: _submitAdd,
            onRemove: (name) =>
                ref.read(watchNotifierProvider.notifier).remove(name),
            onRefresh: () =>
                ref.read(watchNotifierProvider.notifier).refresh(),
          ),
      },
      bottomNavigationBar: watchState is WatchReady
          ? _SaveBar(
              state: watchState,
              readOnlyOffline: watchState.readOnlyOffline,
              onSave: () => ref.read(watchNotifierProvider.notifier).save(),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Ready body
// ---------------------------------------------------------------------------

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({
    required this.state,
    required this.nameController,
    required this.fieldFocus,
    required this.readOnlyOffline,
    required this.onSubmitAdd,
    required this.onRemove,
    required this.onRefresh,
  });

  final WatchReady state;
  final TextEditingController nameController;
  final FocusNode fieldFocus;
  final bool readOnlyOffline;
  final VoidCallback onSubmitAdd;
  final void Function(String name) onRemove;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (readOnlyOffline)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ShowingSavedDataChip(),
            ),
          ),
        _AddNameField(
          controller: nameController,
          focusNode: fieldFocus,
          readOnlyOffline: readOnlyOffline,
          onSubmit: onSubmitAdd,
        ),
        if (state.saveError != null)
          _SaveErrorBanner(error: state.saveError!),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: state.names.isEmpty
                ? _EmptyState()
                : _NameList(
                    names: state.names,
                    isSaving: state.isSaving,
                    readOnlyOffline: readOnlyOffline,
                    onRemove: onRemove,
                  ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add-name text field
// ---------------------------------------------------------------------------

class _AddNameField extends StatelessWidget {
  const _AddNameField({
    required this.controller,
    required this.focusNode,
    required this.readOnlyOffline,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool readOnlyOffline;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  readOnly: readOnlyOffline,
                  enabled: !readOnlyOffline,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Add a place name',
                    hintText: 'e.g. Madina, Lapaz',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: readOnlyOffline ? kOfflineMutationsTooltip : '',
                child: FilledButton.tonal(
                  onPressed: readOnlyOffline ? null : onSubmit,
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          ),
          // Live normalized preview below the field.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final raw = value.text.trim();
              if (raw.isEmpty) return const SizedBox.shrink();
              final normalized = normalizePlaceName(raw);
              return Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'Will match as: $normalized',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Name list (Dismissible tiles)
// ---------------------------------------------------------------------------

class _NameList extends StatelessWidget {
  const _NameList({
    required this.names,
    required this.isSaving,
    required this.readOnlyOffline,
    required this.onRemove,
  });

  final List<String> names;
  final bool isSaving;
  final bool readOnlyOffline;
  final void Function(String) onRemove;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: names.length,
      itemBuilder: (context, index) {
        final name = names[index];
        final normalized = normalizePlaceName(name);
        return Dismissible(
          key: ValueKey(name),
          direction: readOnlyOffline || isSaving
              ? DismissDirection.none
              : DismissDirection.endToStart,
          // Prevent removal while a save is in progress.
          confirmDismiss: isSaving ? (_) async => false : null,
          onDismissed: (_) => onRemove(name),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          child: ListTile(
            title: Text(name),
            subtitle: normalized != name.trim()
                ? Text(
                    'Matches as: $normalized',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  )
                : null,
            trailing: isSaving
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: readOnlyOffline ? null : () => onRemove(name),
                    tooltip: readOnlyOffline
                        ? kOfflineMutationsTooltip
                        : 'Remove',
                  ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView is required for RefreshIndicator to work on empty content.
      children: [
        SizedBox(
          height: 280,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 56,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withAlpha(120),
              ),
              const SizedBox(height: 16),
              Text(
                'No places yet',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add place names above and tap Save.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withAlpha(180),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Save error banner
// ---------------------------------------------------------------------------

class _SaveErrorBanner extends StatelessWidget {
  const _SaveErrorBanner({required this.error});

  final AppError error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final message = error is PlaceLimitError
        ? "You've reached your watch limit — upgrade to add more"
        : error.message;

    return Material(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: colors.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onErrorContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Save bar (bottom)
// ---------------------------------------------------------------------------

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.state,
    required this.readOnlyOffline,
    required this.onSave,
  });

  final WatchReady state;
  final bool readOnlyOffline;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: SizedBox(
          width: double.infinity,
          child: Tooltip(
            message: readOnlyOffline ? kOfflineMutationsTooltip : '',
            child: FilledButton(
              onPressed: state.isSaving || readOnlyOffline ? null : onSave,
              child: state.isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Load-error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load watch list',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
