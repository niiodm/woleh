// DTOs for `/api/v1/me/saved-place-lists` and public share (API_CONTRACT §6.11–§6.12).

class SavedPlaceListSummaryDto {
  const SavedPlaceListSummaryDto({
    required this.id,
    required this.title,
    required this.placeCount,
    required this.shareToken,
    required this.updatedAt,
  });

  final int id;
  final String? title;
  final int placeCount;
  final String shareToken;
  final DateTime updatedAt;

  factory SavedPlaceListSummaryDto.fromJson(Map<String, dynamic> json) =>
      SavedPlaceListSummaryDto(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String?,
        placeCount: (json['placeCount'] as num).toInt(),
        shareToken: json['shareToken'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class SavedPlaceListDetailDto {
  const SavedPlaceListDetailDto({
    required this.id,
    required this.title,
    required this.names,
    required this.shareToken,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String? title;
  final List<String> names;
  final String shareToken;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory SavedPlaceListDetailDto.fromJson(Map<String, dynamic> json) =>
      SavedPlaceListDetailDto(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String?,
        names: List<String>.from(json['names'] as List),
        shareToken: json['shareToken'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class SavedPlaceListPublicDto {
  const SavedPlaceListPublicDto({
    required this.title,
    required this.names,
  });

  final String? title;
  final List<String> names;

  factory SavedPlaceListPublicDto.fromJson(Map<String, dynamic> json) =>
      SavedPlaceListPublicDto(
        title: json['title'] as String?,
        names: List<String>.from(json['names'] as List),
      );
}
