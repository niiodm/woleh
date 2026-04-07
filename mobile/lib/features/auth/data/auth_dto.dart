// DTOs for POST /api/v1/auth/send-otp and POST /api/v1/auth/verify-otp.
// These map directly to the `data` field of the API envelope
// (see API_CONTRACT.md §6.1 and §6.2).

class SendOtpResponse {
  const SendOtpResponse({required this.expiresInSeconds});

  final int expiresInSeconds;

  factory SendOtpResponse.fromJson(Map<String, dynamic> json) =>
      SendOtpResponse(expiresInSeconds: json['expiresInSeconds'] as int);
}

class VerifyOtpResponse {
  const VerifyOtpResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresInSeconds,
    required this.userId,
    required this.flow,
  });

  final String accessToken;
  final String tokenType;
  final int expiresInSeconds;
  final String userId;

  /// `"login"` — existing account; `"signup"` — new account created.
  final String flow;

  bool get isSignup => flow == 'signup';

  factory VerifyOtpResponse.fromJson(Map<String, dynamic> json) =>
      VerifyOtpResponse(
        accessToken: json['accessToken'] as String,
        tokenType: json['tokenType'] as String,
        expiresInSeconds: json['expiresInSeconds'] as int,
        userId: json['userId'].toString(),
        flow: json['flow'] as String,
      );
}
