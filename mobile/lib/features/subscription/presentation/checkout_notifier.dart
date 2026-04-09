import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../me/presentation/me_notifier.dart';
import '../data/subscription_repository.dart';

part 'checkout_notifier.g.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Lifecycle of a single checkout session.
///
/// Transitions: idle → loading → webViewOpen → (polling →) success | failed
sealed class CheckoutState {
  const CheckoutState();
}

final class CheckoutIdle extends CheckoutState {
  const CheckoutIdle();
}

final class CheckoutLoading extends CheckoutState {
  const CheckoutLoading();
}

/// The checkout URL has been obtained; the WebView should load it.
final class CheckoutWebViewOpen extends CheckoutState {
  const CheckoutWebViewOpen({
    required this.checkoutUrl,
    required this.sessionId,
  });

  final String checkoutUrl;
  final String sessionId;
}

/// WebView closed without a deep-link interception; polling GET /me once
/// as a fallback to catch delayed webhooks.
final class CheckoutPolling extends CheckoutState {
  const CheckoutPolling();
}

final class CheckoutSuccess extends CheckoutState {
  const CheckoutSuccess();
}

final class CheckoutFailed extends CheckoutState {
  const CheckoutFailed({required this.message});

  final String message;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

@riverpod
class CheckoutNotifier extends _$CheckoutNotifier {
  @override
  CheckoutState build() => const CheckoutIdle();

  /// Calls `POST /subscription/checkout` and moves to [CheckoutWebViewOpen].
  Future<void> startCheckout(String planId) async {
    state = const CheckoutLoading();
    try {
      final response = await ref
          .read(subscriptionRepositoryProvider)
          .startCheckout(planId);
      state = CheckoutWebViewOpen(
        checkoutUrl: response.checkoutUrl,
        sessionId: response.sessionId,
      );
    } catch (e) {
      state = CheckoutFailed(message: _friendlyError(e));
    }
  }

  /// Called when the WebView intercepts the `woleh://subscription/result`
  /// deep-link redirect from the payment provider (or stub).
  void onPaymentResult({required bool success}) {
    if (success) {
      state = const CheckoutSuccess();
      // Refresh entitlements so GET /me reflects the new paid tier.
      ref.read(meNotifierProvider.notifier).refresh();
    } else {
      state = const CheckoutFailed(message: 'Payment was not completed.');
    }
  }

  /// Called when the user dismisses the WebView without a deep-link intercept.
  /// Polls GET /me once as a fallback for delayed webhooks.
  Future<void> onWebViewClosed() async {
    if (state is! CheckoutWebViewOpen) return;
    state = const CheckoutPolling();
    try {
      await ref.read(meNotifierProvider.notifier).refresh();
      final tier = ref.read(meNotifierProvider).valueOrNull?.tier;
      if (tier == 'paid') {
        state = const CheckoutSuccess();
      } else {
        // Webhook not yet processed; let the user retry or check later.
        state = const CheckoutIdle();
      }
    } catch (_) {
      state = const CheckoutIdle();
    }
  }

  /// Resets back to [CheckoutIdle] (e.g. when user navigates away).
  void reset() => state = const CheckoutIdle();

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('403')) return 'You need an active plan to subscribe.';
    if (msg.contains('400')) return 'Invalid plan. Please try again.';
    if (msg.contains('NetworkError') || msg.contains('SocketException')) {
      return 'No internet connection.';
    }
    return 'Something went wrong. Please try again.';
  }
}
