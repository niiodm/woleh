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
    required this.refreshToken,
  });

  final String accessToken;
  final String tokenType;
  final int expiresInSeconds;
  final String userId;

  /// `"login"` — existing account; `"signup"` — new account created.
  final String flow;

  /// Opaque refresh token for obtaining new access tokens (FR-A2).
  final String refreshToken;

  bool get isSignup => flow == 'signup';

  factory VerifyOtpResponse.fromJson(Map<String, dynamic> json) =>
      VerifyOtpResponse(
        accessToken: json['accessToken'] as String,
        tokenType: json['tokenType'] as String,
        expiresInSeconds: json['expiresInSeconds'] as int,
        userId: json['userId'].toString(),
        flow: json['flow'] as String,
        refreshToken: json['refreshToken'] as String,
      );
}

/// Response body for `POST /api/v1/auth/refresh`.
class RefreshResponse {
  const RefreshResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;

  /// Seconds until the new access token expires.
  final int expiresIn;

  factory RefreshResponse.fromJson(Map<String, dynamic> json) =>
      RefreshResponse(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresIn: json['expiresIn'] as int,
      );
}
