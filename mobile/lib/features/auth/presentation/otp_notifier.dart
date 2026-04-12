import 'dart:async';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/app_error.dart';
import '../data/auth_dto.dart';
import '../data/auth_repository.dart';

part 'otp_notifier.g.dart';

enum OtpActionStatus { idle, verifying, resending, error }

class OtpState {
  const OtpState({
    this.status = OtpActionStatus.idle,
    this.countdownSeconds = 0,
    this.errorMessage,
  });

  final OtpActionStatus status;
  final int countdownSeconds;
  final String? errorMessage;

  bool get isLoading =>
      status == OtpActionStatus.verifying || status == OtpActionStatus.resending;

  bool get canResend =>
      countdownSeconds <= 0 && status == OtpActionStatus.idle;

  OtpState withCountdown(int seconds) =>
      OtpState(status: status, countdownSeconds: seconds, errorMessage: errorMessage);

  OtpState withStatus(OtpActionStatus s) =>
      OtpState(status: s, countdownSeconds: countdownSeconds, errorMessage: errorMessage);

  OtpState withError(String msg) =>
      OtpState(status: OtpActionStatus.error, countdownSeconds: countdownSeconds, errorMessage: msg);
}

/// Notifier for the OTP entry screen.
///
/// Constructed as a family keyed by [phoneE164] so that the countdown and
/// error state are scoped to one phone session.
@riverpod
class OtpNotifier extends _$OtpNotifier {
  Timer? _countdownTimer;

  @override
  OtpState build(String phoneE164) {
    ref.onDispose(() => _countdownTimer?.cancel());
    return const OtpState();
  }

  void startCountdown(int seconds) {
    _countdownTimer?.cancel();
    state = state.withCountdown(seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.countdownSeconds - 1;
      if (remaining <= 0) {
        _countdownTimer?.cancel();
        state = state.withCountdown(0);
      } else {
        state = state.withCountdown(remaining);
      }
    });
  }

  /// Verifies the OTP. Returns the response on success, null on failure.
  Future<VerifyOtpResponse?> verify(
    String otp, {
    bool? productAnalyticsConsent,
  }) async {
    state = state.withStatus(OtpActionStatus.verifying);
    try {
      final result = await ref.read(authRepositoryProvider).verifyOtp(
            phoneE164: phoneE164,
            otp: otp,
            productAnalyticsConsent: productAnalyticsConsent,
          );
      _countdownTimer?.cancel();
      state = state.withCountdown(0).withStatus(OtpActionStatus.idle);
      return result;
    } catch (e) {
      state = state.withError(_extractAppError(e).message);
      return null;
    }
  }

  /// Resends the OTP to [phoneE164] and restarts the countdown.
  Future<void> resend() async {
    state = state.withStatus(OtpActionStatus.resending);
    try {
      final result =
          await ref.read(authRepositoryProvider).sendOtp(phoneE164);
      state = OtpState(); // reset error
      startCountdown(result.expiresInSeconds);
    } catch (e) {
      state = state.withError(_extractAppError(e).message);
    }
  }

  void clearError() => state = state.withStatus(OtpActionStatus.idle);
}

AppError _extractAppError(Object err) {
  if (err is DioException && err.error is AppError) return err.error as AppError;
  if (err is AppError) return err;
  return UnknownError(err.toString());
}
