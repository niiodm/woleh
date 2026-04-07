import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/app_error.dart';
import '../data/auth_repository.dart';
import '../data/auth_dto.dart';

part 'phone_notifier.g.dart';

enum PhoneSendStatus { idle, loading, error }

class PhoneState {
  const PhoneState({
    this.status = PhoneSendStatus.idle,
    this.errorMessage,
  });

  final PhoneSendStatus status;
  final String? errorMessage;

  bool get isLoading => status == PhoneSendStatus.loading;
}

@riverpod
class PhoneNotifier extends _$PhoneNotifier {
  @override
  PhoneState build() => const PhoneState();

  /// Calls `POST /auth/send-otp` and returns the response on success,
  /// or null and sets an error message on failure.
  Future<SendOtpResponse?> sendOtp(String phoneE164) async {
    state = const PhoneState(status: PhoneSendStatus.loading);
    try {
      final result =
          await ref.read(authRepositoryProvider).sendOtp(phoneE164);
      state = const PhoneState();
      return result;
    } catch (e) {
      final appError = _extractAppError(e);
      state = PhoneState(
        status: PhoneSendStatus.error,
        errorMessage: appError.message,
      );
      return null;
    }
  }

  void clearError() => state = const PhoneState();
}

AppError _extractAppError(Object err) {
  if (err is DioException && err.error is AppError) return err.error as AppError;
  if (err is AppError) return err;
  return UnknownError(err.toString());
}
