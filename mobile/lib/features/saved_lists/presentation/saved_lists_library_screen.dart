import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics_provider.dart';
import '../data/saved_place_list_repository.dart';
import 'saved_list_qr_screen.dart';
import 'saved_place_list_summaries_provider.dart';

/// Lists persisted saved place templates; entry to create, edit, share, scan.
class SavedListsLibraryScreen extends ConsumerWidget {
  const SavedListsLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(savedPlaceListSummariesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved lists'),
        actions: [
          IconButton(
            tooltip: 'Scan QR',
            icon: const Icon(Icons.qr_code_scanner_outlined),
            onPressed: () {
              unawaited(
                ref.read(wolehAnalyticsProvider).logButtonTapped(
                      'saved_lists_scan',
                      screenName: '/saved-lists',
                    ),
              );
              context.push('/saved-lists/scan');
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(savedPlaceListSummariesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'No saved lists yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a list to reuse places or share via QR.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(savedPlaceListSummariesProvider);
              await ref.read(savedPlaceListSummariesProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final s = rows[i];
                final title = s.title?.isNotEmpty == true
                    ? s.title!
                    : 'Untitled list';
                return ListTile(
                  title: Text(title),
                  subtitle: Text(
                    '${s.placeCount} places · Updated ${_shortDate(s.updatedAt)}',
                  ),
                  onTap: () => context.push('/saved-lists/edit/${s.id}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'qr') {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => SavedListQrScreen(
                              title: title,
                              shareToken: s.shareToken,
                            ),
                          ),
                        );
                      } else if (value == 'delete') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete list?'),
                            content: Text('Remove “$title” from your saved lists?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          try {
                            await ref
                                .read(savedPlaceListRepositoryProvider)
                                .delete(s.id);
                            if (context.mounted) {
                              ref.invalidate(savedPlaceListSummariesProvider);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          }
                        }
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'qr',
                        child: Text('Show QR code'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          unawaited(
            ref.read(wolehAnalyticsProvider).logButtonTapped(
                  'saved_lists_create',
                  screenName: '/saved-lists',
                ),
          );
          context.push('/saved-lists/create');
        },
        icon: const Icon(Icons.add),
        label: const Text('New list'),
      ),
    );
  }
}

String _shortDate(DateTime t) {
  final l = t.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}
