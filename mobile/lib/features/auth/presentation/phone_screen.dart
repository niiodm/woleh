import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics_provider.dart';
import '../../../core/phone_utils.dart';
import '../../../core/telemetry_consent.dart';
import '../../../core/telemetry_consent_provider.dart';
import 'phone_notifier.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  var _productAnalyticsConsent = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter a phone number';
    final normalized = normalizePhone(value);
    if (!isValidE164(normalized)) return 'Enter a valid phone number (e.g. 0241234567)';
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    unawaited(
      ref.read(wolehAnalyticsProvider).logButtonTapped(
            'send_otp',
            screenName: '/auth/phone',
          ),
    );
    final consentForDevice =
        kSkipTelemetryConsentPrompt ? true : _productAnalyticsConsent;
    if (!kSkipTelemetryConsentPrompt) {
      await ref
          .read(telemetryConsentProvider.notifier)
          .setProductAnalyticsAllowed(consentForDevice);
    }
    final phone = normalizePhone(_controller.text);
    final result = await ref.read(phoneNotifierProvider.notifier).sendOtp(phone);
    if (result != null && mounted) {
      context.go(
        '/auth/otp',
        extra: {
          'phone': phone,
          'expiresInSeconds': result.expiresInSeconds,
          'productAnalyticsConsent': consentForDevice,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phoneNotifierProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter your phone number',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  "We'll send a one-time code to verify it's you.",
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '0241234567 or +233241234567',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  validator: _validatePhone,
                ),
                if (!kSkipTelemetryConsentPrompt) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _productAnalyticsConsent,
                    onChanged: state.isLoading
                        ? null
                        : (v) => setState(() {
                              _productAnalyticsConsent = v ?? false;
                            }),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Product analytics'),
                    subtitle: Text(
                      'Help improve the app with anonymous usage and screen views. '
                      'You can change this anytime in Profile.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    'Product analytics follows WOLEH_SKIP_TELEMETRY_CONSENT for this build.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                if (state.status == PhoneSendStatus.error && state.errorMessage != null)
                  _ErrorBanner(state.errorMessage!),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: state.isLoading ? null : _submit,
                  child: state.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send code'),
                ),
              ],
            ),
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
