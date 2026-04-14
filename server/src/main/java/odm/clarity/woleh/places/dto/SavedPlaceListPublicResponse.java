package odm.clarity.woleh.places.dto;

import java.util.List;

/** Unauthenticated read by share token. */
public record SavedPlaceListPublicResponse(String title, List<String> names) {
}
