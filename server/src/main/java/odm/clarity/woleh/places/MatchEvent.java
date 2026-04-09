package odm.clarity.woleh.places;

import java.util.List;

/**
 * Data payload for a {@code match} WebSocket event (API_CONTRACT.md §8.1).
 * Serialised as the {@code data} field inside a {@code WsEnvelope}.
 *
 * <ul>
 *   <li>{@code matchedNames} — normalized place names found in the intersection.</li>
 *   <li>{@code counterpartyUserId} — the user whose complementary list triggered the match.</li>
 *   <li>{@code kind} — relationship direction; {@code "broadcast_to_watch"} is the v1 value.</li>
 * </ul>
 */
public record MatchEvent(
		List<String> matchedNames,
		String counterpartyUserId,
		String kind) {
}
