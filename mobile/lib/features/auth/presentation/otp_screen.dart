import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics_provider.dart';
import '../../../core/auth_state.dart';
import 'otp_notifier.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({
    super.key,
    required this.phone,
    required this.expiresInSeconds,
  });

  final String phone;
  final int expiresInSeconds;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Start the countdown as soon as this screen mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(otpNotifierProvider(widget.phone).notifier)
          .startCountdown(widget.expiresInSeconds);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validateOtp(String? value) {
    if (value == null || value.trim().isEmpty) return 'Verification code is required';
    if (value.trim().length != 6) return 'Verification code must be 6 digits';
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final otp = _controller.text.trim();
    final result = await ref
        .read(otpNotifierProvider(widget.phone).notifier)
        .verify(otp);
    if (result == null || !mounted) return;

    // Persist access + refresh tokens — triggers router redirect.
    await ref
        .read(authStateProvider.notifier)
        .setTokens(result.accessToken, result.refreshToken);

    unawaited(
      ref.read(wolehAnalyticsProvider).logEvent('auth_completed', {
        'is_signup': result.isSignup ? 1 : 0,
      }),
    );

    if (!mounted) return;
    if (result.isSignup) {
      context.go('/auth/setup-name');
    }
    // For login, the router's redirect fires automatically once the token is set.
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(otpNotifierProvider(widget.phone));
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify your number'),
        leading: BackButton(onPressed: () => context.go('/auth/phone')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter the 6-digit code',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a verification code to ${widget.phone}.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  textInputAction: TextInputAction.done,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(letterSpacing: 8),
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  validator: _validateOtp,
                ),
                const SizedBox(height: 16),
                if (state.status == OtpActionStatus.error &&
                    state.errorMessage != null)
                  _ErrorBanner(state.errorMessage!),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: state.isLoading
                      ? null
                      : () {
                          unawaited(
                            ref.read(wolehAnalyticsProvider).logButtonTapped(
                                  'verify_otp',
                                  screenName: '/auth/otp',
                                ),
                          );
                          _submit();
                        },
                  child: state.status == OtpActionStatus.verifying
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify'),
                ),
                const SizedBox(height: 24),
                _ResendRow(
                  phone: widget.phone,
                  state: state,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResendRow extends ConsumerWidget {
  const _ResendRow({required this.phone, required this.state});

  final String phone;
  final OtpState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    if (state.status == OtpActionStatus.resending) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.countdownSeconds > 0) {
      final minutes = state.countdownSeconds ~/ 60;
      final seconds = state.countdownSeconds % 60;
      final label =
          minutes > 0 ? '$minutes:${seconds.toString().padLeft(2, '0')}' : '${seconds}s';
      return Center(
        child: Text(
          'Resend code in $label',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
      );
    }

    return Center(
      child: TextButton(
        onPressed: state.isLoading
            ? null
            : () {
                unawaited(
                  ref.read(wolehAnalyticsProvider).logButtonTapped(
                        'resend_otp',
                        screenName: '/auth/otp',
                      ),
                );
                ref.read(otpNotifierProvider(phone).notifier).resend();
              },
        child: const Text('Resend code'),
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
