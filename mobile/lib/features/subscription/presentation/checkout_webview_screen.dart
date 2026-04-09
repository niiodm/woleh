import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'checkout_notifier.dart';

/// Handles the full checkout lifecycle for a given [planId]:
///   1. Calls `POST /subscription/checkout` to obtain the provider URL.
///   2. Opens the URL in an in-app WebView (lazily created on first use).
///   3. Intercepts the `woleh://subscription/result` deep link to detect outcome.
///   4. On success: refreshes entitlements and navigates to home.
///   5. On failure / close: shows a retry option.
class CheckoutWebViewScreen extends ConsumerStatefulWidget {
  const CheckoutWebViewScreen({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<CheckoutWebViewScreen> createState() =>
      _CheckoutWebViewScreenState();
}

class _CheckoutWebViewScreenState
    extends ConsumerState<CheckoutWebViewScreen> {
  /// Created lazily when the checkout URL is first available, so platform
  /// initialisation is not required in environments without a WebView platform
  /// (e.g. unit tests that only exercise loading / error states).
  WebViewController? _webViewController;

  /// Ensures the [WebViewController] is created exactly once and configured
  /// with the navigation delegate that intercepts the payment deep link.
  WebViewController _getOrCreateController() {
    if (_webViewController != null) return _webViewController!;
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onNavigationRequest: _handleNavigationRequest),
      );
    return _webViewController!;
  }

  @override
  void initState() {
    super.initState();
    // Trigger checkout after the first frame so ref is fully bound.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(checkoutNotifierProvider.notifier)
          .startCheckout(widget.planId);
    });
  }

  NavigationDecision _handleNavigationRequest(NavigationRequest request) {
    if (!request.url.startsWith('woleh://')) {
      return NavigationDecision.navigate;
    }
    // Intercept: woleh://subscription/result?status=success|failure
    final uri = Uri.tryParse(request.url);
    final success = uri?.queryParameters['status'] == 'success';
    if (mounted) {
      ref
          .read(checkoutNotifierProvider.notifier)
          .onPaymentResult(success: success);
    }
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) {
    final checkoutState = ref.watch(checkoutNotifierProvider);

    // React to state transitions requiring navigation or WebView URL loading.
    ref.listen<CheckoutState>(checkoutNotifierProvider, (prev, next) {
      if (next is CheckoutWebViewOpen) {
        _getOrCreateController().loadRequest(Uri.parse(next.checkoutUrl));
        // Trigger a rebuild so the WebView widget is swapped in.
        if (mounted) setState(() {});
      } else if (next is CheckoutSuccess) {
        _showSuccessAndNavigate(context);
      }
    });

    return PopScope(
      canPop: checkoutState is! CheckoutWebViewOpen,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await ref.read(checkoutNotifierProvider.notifier).onWebViewClosed();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Complete payment'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: () async {
              ref.read(checkoutNotifierProvider.notifier).reset();
              if (context.mounted) context.go('/plans');
            },
          ),
        ),
        body: _buildBody(checkoutState),
      ),
    );
  }

  Widget _buildBody(CheckoutState state) {
    final isWebViewActive =
        state is CheckoutWebViewOpen && _webViewController != null;

    // Keep WebViewWidget in the widget tree once the controller is created,
    // even when transitioning to other states, to avoid MouseTracker pointer-
    // event desync on Android caused by Platform Views being torn down while
    // the pointer device is still tracked (flutter/flutter#130586).
    return Stack(
      children: [
        if (_webViewController != null)
          Offstage(
            offstage: !isWebViewActive,
            child: WebViewWidget(controller: _webViewController!),
          ),
        if (!isWebViewActive)
          switch (state) {
            CheckoutIdle() || CheckoutLoading() => const _LoadingView(),
            // Controller not yet assigned (listen fires after build on first frame).
            CheckoutWebViewOpen() => const _LoadingView(),
            CheckoutPolling() => const _PollingView(),
            CheckoutSuccess() => const _LoadingView(), // briefly shown; nav fires
            CheckoutFailed(:final message) => _FailureView(
                message: message,
                onRetry: () {
                  ref
                      .read(checkoutNotifierProvider.notifier)
                      .startCheckout(widget.planId);
                },
              ),
          },
      ],
    );
  }

  void _showSuccessAndNavigate(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Subscription activated! Welcome to Woleh Pro.'),
        duration: Duration(seconds: 4),
      ),
    );
    context.go('/home');
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => const Center(
        child: CircularProgressIndicator(),
      );
}

class _PollingView extends StatelessWidget {
  const _PollingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Verifying payment…',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a few seconds.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.message, required this.onRetry});

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
            Icon(Icons.error_outline,
                size: 56,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Payment not completed',
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => GoRouter.of(context).go('/plans'),
                  child: const Text('Back to plans'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
