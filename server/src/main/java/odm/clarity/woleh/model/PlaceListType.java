package odm.clarity.woleh.model;

/**
 * Discriminates the two place-name list kinds stored in {@code user_place_lists}.
 *
 * <ul>
 *   <li>{@link #WATCH} — unordered set of places a rider wants to see service for.</li>
 *   <li>{@link #BROADCAST} — ordered sequence of places a vehicle operator will drive through.</li>
 * </ul>
 */
public enum PlaceListType {
	WATCH,
	BROADCAST
}
