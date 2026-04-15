import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/auth_state.dart';
import '../../../core/shared_preferences_provider.dart';
import '../../../features/me/data/me_dto.dart';
import '../../../features/me/presentation/me_notifier.dart';
import '../data/saved_list_share_url.dart';
import 'pending_saved_list_import_provider.dart';

/// Builds the import route for a share token.
String savedListImportPath(String token) =>
    '/saved-lists/import?token=${Uri.encodeQueryComponent(token)}';

bool _alwaysMounted() => true;

/// Parses `woleh://saved-lists/...` and updates [pendingSavedListImportTokenProvider].
/// Does not navigate while [authStateProvider] is still loading.
///
/// Exposed for tests; production uses [SavedListDeepLinkScope].
void routeSavedListShareFromUri(
  WidgetRef ref,
  Uri uri, {
  bool Function() isMounted = _alwaysMounted,
}) {
  if (uri.scheme != 'woleh') return;
  if (uri.host == 'subscription') return;
  if (uri.host != 'saved-lists') return;
  final token = parseSavedListShareToken(uri.toString());
  if (token == null || token.isEmpty) return;

  ref.read(pendingSavedListImportTokenProvider.notifier).state = token;

  final auth = ref.read(authStateProvider);
  if (auth.isLoading) return;

  if (auth.valueOrNull == null) {
    ref.read(routerProvider).go('/auth/phone');
    return;
  }

  schedulePendingSavedListImportNavigation(ref, isMounted: isMounted);
}

/// When pending token is set and auth + `/me` allow a landing route, runs
/// `go(landing)` then `push(import)` (or `push` only if already on landing).
void schedulePendingSavedListImportNavigation(
  WidgetRef ref, {
  required bool Function() isMounted,
}) {
  final pending = ref.read(pendingSavedListImportTokenProvider);
  if (pending == null || pending.isEmpty) return;

  final auth = ref.read(authStateProvider);
  if (auth.isLoading) return;
  if (auth.valueOrNull == null) return;

  final landing = authenticatedLandingFromMeAndPrefs(
    meAsync: ref.read(meNotifierProvider),
    prefs: ref.read(sharedPreferencesProvider),
  );
  if (landing == null) return;

  final router = ref.read(routerProvider);
  final loc = router.state.matchedLocation;
  final path = savedListImportPath(pending);

  final importTokenParam = router.state.uri.queryParameters['token'] ?? '';
  if (loc == '/saved-lists/import' && importTokenParam == pending) {
    ref.read(pendingSavedListImportTokenProvider.notifier).state = null;
    return;
  }

  if (loc == '/splash') {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted()) return;
      schedulePendingSavedListImportNavigation(ref, isMounted: isMounted);
    });
    return;
  }

  ref.read(pendingSavedListImportTokenProvider.notifier).state = null;

  if (loc == landing) {
    router.push(path);
  } else {
    router.go(landing);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted()) return;
      ref.read(routerProvider).push(path);
    });
  }
}

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
    final appLinks = AppLinks();
    unawaited(_handleInitial(appLinks));
    _sub = appLinks.uriLinkStream.listen(_onUri);
  }

  Future<void> _handleInitial(AppLinks appLinks) async {
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) {
        routeSavedListShareFromUri(ref, initial, isMounted: () => mounted);
      }
    } catch (_) {}
  }

  void _onUri(Uri uri) =>
      routeSavedListShareFromUri(ref, uri, isMounted: () => mounted);

  @override
  void dispose() {
    unawaited(_sub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  void _scheduleConsumePending() {
    schedulePendingSavedListImportNavigation(
      ref,
      isMounted: () => mounted,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<String?>>(authStateProvider, (_, __) {
      _scheduleConsumePending();
    });
    ref.listen<AsyncValue<MeLoadSnapshot?>>(meNotifierProvider, (_, __) {
      _scheduleConsumePending();
    });

    return widget.child;
  }
}
