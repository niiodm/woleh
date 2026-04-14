import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/auth_state.dart';
import '../data/saved_list_share_url.dart';
import 'pending_saved_list_import_provider.dart';

/// Handles `woleh://saved-lists/{token}` without consuming `woleh://subscription/...`.
class SavedListDeepLinkScope extends ConsumerStatefulWidget {
  const SavedListDeepLinkScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SavedListDeepLinkScope> createState() =>
      _SavedListDeepLinkScopeState();
}

class _SavedListDeepLinkScopeState extends ConsumerState<SavedListDeepLinkScope> {
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    unawaited(_bindAppLinks());
  }

  /// Handle cold-start [getInitialLink] first, then subscribe — avoids the same
  /// URI being processed twice on some devices (double [push] / odd stacks).
  Future<void> _bindAppLinks() async {
    final appLinks = AppLinks();
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) _routeShare(initial);
    } catch (_) {}
    _sub = appLinks.uriLinkStream.listen(_onUri);
  }

  void _onUri(Uri uri) => _routeShare(uri);

  void _routeShare(Uri uri) {
    if (uri.scheme != 'woleh') return;
    if (uri.host == 'subscription') return;
    if (uri.host != 'saved-lists') return;
    final token = parseSavedListShareToken(uri.toString());
    if (token == null || token.isEmpty) return;

    final auth = ref.read(authStateProvider);
    final router = ref.read(routerProvider);
    if (auth.valueOrNull != null) {
      router.push(
        '/saved-lists/import?token=${Uri.encodeQueryComponent(token)}',
      );
    } else {
      ref.read(pendingSavedListImportTokenProvider.notifier).state = token;
      router.go('/auth/phone');
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<String?>>(authStateProvider, (prev, next) {
      final wasOut = prev?.valueOrNull == null;
      final nowIn = next.valueOrNull != null;
      if (!wasOut || !nowIn) return;
      final pending = ref.read(pendingSavedListImportTokenProvider);
      if (pending == null || pending.isEmpty) return;
      ref.read(pendingSavedListImportTokenProvider.notifier).state = null;
      final router = ref.read(routerProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        router.push(
          '/saved-lists/import?token=${Uri.encodeQueryComponent(pending)}',
        );
      });
    });

    return widget.child;
  }
}
