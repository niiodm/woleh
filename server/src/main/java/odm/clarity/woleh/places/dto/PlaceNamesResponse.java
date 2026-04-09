package odm.clarity.woleh.places.dto;

import java.util.List;

/** Response shape for GET and PUT place-name list endpoints (API_CONTRACT.md §6.7–§6.10). */
public record PlaceNamesResponse(List<String> names) {
}
