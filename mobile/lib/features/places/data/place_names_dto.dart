// DTO for GET/PUT /api/v1/me/places/watch and /api/v1/me/places/broadcast
// (API_CONTRACT.md §6.7–§6.10).
//
// Both endpoints share the same request and response shape:
//   Request body:  { "names": [ ... ] }
//   Response data: { "names": [ ... ] }
//
// The `names` list is in the display form entered by the user (not normalized).
// Watch list: unordered set semantics (server deduplicates by normalized form).
// Broadcast list: ordered sequence (order is preserved; duplicates rejected 400).

class PlaceNamesDto {
  const PlaceNamesDto({required this.names});

  final List<String> names;

  factory PlaceNamesDto.fromJson(Map<String, dynamic> json) =>
      PlaceNamesDto(names: List<String>.from(json['names'] as List));

  Map<String, dynamic> toJson() => {'names': names};
}
