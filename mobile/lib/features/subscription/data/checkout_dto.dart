// DTOs for POST /api/v1/subscription/checkout (see API_CONTRACT.md §6.6).

class CheckoutResponse {
  const CheckoutResponse({
    required this.checkoutUrl,
    required this.sessionId,
    required this.expiresAt,
  });

  final String checkoutUrl;
  final String sessionId;
  final String expiresAt;

  factory CheckoutResponse.fromJson(Map<String, dynamic> json) => CheckoutResponse(
        checkoutUrl: json['checkoutUrl'] as String,
        sessionId: json['sessionId'] as String,
        expiresAt: json['expiresAt'] as String,
      );
}
