import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:odm_clarity_woleh_mobile/features/me/data/me_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/me/presentation/me_notifier.dart';
import 'package:odm_clarity_woleh_mobile/features/subscription/data/checkout_dto.dart';
import 'package:odm_clarity_woleh_mobile/features/subscription/data/subscription_repository.dart';
import 'package:odm_clarity_woleh_mobile/features/subscription/presentation/checkout_notifier.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _StubSubscriptionRepository extends SubscriptionRepository {
  _StubSubscriptionRepository({this.throwError = false}) : super(Dio());

  final bool throwError;

  static const _fakeResponse = CheckoutResponse(
    checkoutUrl: 'https://pay.stub.example/checkout/test123',
    sessionId: 'session-abc',
    expiresAt: '2026-04-09T12:00:00Z',
  );

  @override
  Future<CheckoutResponse> startCheckout(String planId) async {
    if (throwError) throw Exception('Network error');
    return _fakeResponse;
  }
}

class _FreeMeNotifier extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
        me: const MeResponse(
          profile: MeProfile(userId: '1', phoneE164: '+233241234567'),
          permissions: [
            'woleh.account.profile',
            'woleh.plans.read',
            'woleh.place.watch',
          ],
          tier: 'free',
          limits: MeLimits(placeWatchMax: 5, placeBroadcastMax: 0),
          subscription: MeSubscription(status: 'none', inGracePeriod: false),
        ),
      );
}

class _PaidMeNotifier extends MeNotifier {
  @override
  Future<MeLoadSnapshot?> build() async => MeLoadSnapshot(
        me: const MeResponse(
          profile: MeProfile(userId: '1', phoneE164: '+233241234567'),
          permissions: [
            'woleh.account.profile',
            'woleh.plans.read',
            'woleh.place.watch',
            'woleh.place.broadcast',
          ],
          tier: 'paid',
          limits: MeLimits(placeWatchMax: 50, placeBroadcastMax: 50),
          subscription: MeSubscription(
            status: 'active',
            currentPeriodEnd: '2026-05-09T00:00:00Z',
            inGracePeriod: false,
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({
  bool repoThrows = false,
  bool paidTier = false,
}) {
  return ProviderContainer(
    overrides: [
      subscriptionRepositoryProvider.overrideWith(
        (_) => _StubSubscriptionRepository(throwError: repoThrows),
      ),
      meNotifierProvider.overrideWith(
        paidTier ? _PaidMeNotifier.new : _FreeMeNotifier.new,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CheckoutNotifier', () {
    test('initial state is CheckoutIdle', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      expect(container.read(checkoutNotifierProvider), isA<CheckoutIdle>());
    });

    test('startCheckout transitions idle → loading → webViewOpen on success',
        () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final states = <CheckoutState>[];
      container.listen(checkoutNotifierProvider, (_, next) => states.add(next),
          fireImmediately: true);

      await container
          .read(checkoutNotifierProvider.notifier)
          .startCheckout('woleh_paid_monthly');

      expect(states[0], isA<CheckoutIdle>());
      expect(states[1], isA<CheckoutLoading>());
      expect(states[2], isA<CheckoutWebViewOpen>());

      final open = states[2] as CheckoutWebViewOpen;
      expect(open.checkoutUrl,
          equals('https://pay.stub.example/checkout/test123'));
      expect(open.sessionId, equals('session-abc'));
    });

    test('startCheckout transitions to CheckoutFailed on repository error',
        () async {
      final container = _makeContainer(repoThrows: true);
      addTearDown(container.dispose);

      await container
          .read(checkoutNotifierProvider.notifier)
          .startCheckout('woleh_paid_monthly');

      expect(container.read(checkoutNotifierProvider), isA<CheckoutFailed>());
    });

    test('onPaymentResult(success: true) moves to CheckoutSuccess', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await container
          .read(checkoutNotifierProvider.notifier)
          .startCheckout('woleh_paid_monthly');

      container
          .read(checkoutNotifierProvider.notifier)
          .onPaymentResult(success: true);

      expect(container.read(checkoutNotifierProvider), isA<CheckoutSuccess>());
    });

    test('onPaymentResult(success: false) moves to CheckoutFailed', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await container
          .read(checkoutNotifierProvider.notifier)
          .startCheckout('woleh_paid_monthly');

      container
          .read(checkoutNotifierProvider.notifier)
          .onPaymentResult(success: false);

      final state = container.read(checkoutNotifierProvider);
      expect(state, isA<CheckoutFailed>());
      expect((state as CheckoutFailed).message,
          contains('Payment was not completed'));
    });

    test('onWebViewClosed when paid me refreshes → moves to CheckoutSuccess',
        () async {
      final container = _makeContainer(paidTier: true);
      addTearDown(container.dispose);

      // Manually put notifier into webViewOpen state first.
      await container
          .read(checkoutNotifierProvider.notifier)
          .startCheckout('woleh_paid_monthly');

      // Simulate user closing WebView; stub returns paid tier on refresh.
      await container
          .read(checkoutNotifierProvider.notifier)
          .onWebViewClosed();

      expect(container.read(checkoutNotifierProvider), isA<CheckoutSuccess>());
    });

    test('onWebViewClosed when free me refreshes → returns to CheckoutIdle',
        () async {
      final container = _makeContainer(paidTier: false);
      addTearDown(container.dispose);

      await container
          .read(checkoutNotifierProvider.notifier)
          .startCheckout('woleh_paid_monthly');

      await container
          .read(checkoutNotifierProvider.notifier)
          .onWebViewClosed();

      expect(container.read(checkoutNotifierProvider), isA<CheckoutIdle>());
    });

    test('reset() returns state to CheckoutIdle', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await container
          .read(checkoutNotifierProvider.notifier)
          .startCheckout('woleh_paid_monthly');

      container.read(checkoutNotifierProvider.notifier).reset();

      expect(container.read(checkoutNotifierProvider), isA<CheckoutIdle>());
    });
  });

  group('NavigationDelegate intercept logic', () {
    test('woleh:// URL with status=success calls onPaymentResult(success: true)',
        () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await container
          .read(checkoutNotifierProvider.notifier)
          .startCheckout('woleh_paid_monthly');

      // Simulate what the NavigationDelegate does when the WebView intercepts
      // woleh://subscription/result?status=success
      const deepLink = 'woleh://subscription/result?status=success';
      final uri = Uri.parse(deepLink);
      final success = uri.queryParameters['status'] == 'success';

      container
          .read(checkoutNotifierProvider.notifier)
          .onPaymentResult(success: success);

      expect(container.read(checkoutNotifierProvider), isA<CheckoutSuccess>());
    });

    test('woleh:// URL with status=failure calls onPaymentResult(success: false)',
        () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await container
          .read(checkoutNotifierProvider.notifier)
          .startCheckout('woleh_paid_monthly');

      const deepLink = 'woleh://subscription/result?status=failure';
      final uri = Uri.parse(deepLink);
      final success = uri.queryParameters['status'] == 'success';

      container
          .read(checkoutNotifierProvider.notifier)
          .onPaymentResult(success: success);

      expect(container.read(checkoutNotifierProvider), isA<CheckoutFailed>());
    });
  });
}
