// DTOs for GET /api/v1/subscription/plans (see API_CONTRACT.md §6.5).

class PlanPrice {
  const PlanPrice({required this.amountMinor, required this.currency});

  final int amountMinor;
  final String currency;

  factory PlanPrice.fromJson(Map<String, dynamic> json) => PlanPrice(
        amountMinor: json['amountMinor'] as int,
        currency: json['currency'] as String,
      );
}

class PlanLimits {
  const PlanLimits({
    required this.placeWatchMax,
    required this.placeBroadcastMax,
  });

  final int placeWatchMax;
  final int placeBroadcastMax;

  factory PlanLimits.fromJson(Map<String, dynamic> json) => PlanLimits(
        placeWatchMax: json['placeWatchMax'] as int,
        placeBroadcastMax: json['placeBroadcastMax'] as int,
      );
}

class PlanDto {
  const PlanDto({
    required this.planId,
    required this.displayName,
    required this.permissionsGranted,
    required this.limits,
    required this.price,
  });

  final String planId;
  final String displayName;
  final List<String> permissionsGranted;
  final PlanLimits limits;
  final PlanPrice price;

  /// Whether this plan is the free tier (price is zero).
  bool get isFree => price.amountMinor == 0;

  factory PlanDto.fromJson(Map<String, dynamic> json) => PlanDto(
        planId: json['planId'] as String,
        displayName: json['displayName'] as String,
        permissionsGranted:
            List<String>.from(json['permissionsGranted'] as List),
        limits: PlanLimits.fromJson(json['limits'] as Map<String, dynamic>),
        price: PlanPrice.fromJson(json['price'] as Map<String, dynamic>),
      );
}
