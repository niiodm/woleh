package odm.clarity.woleh.ws;

/**
 * JSON envelope for all outbound WebSocket messages (API_CONTRACT.md §8).
 *
 * <pre>{@code { "type": "heartbeat",     "data": "ping" }
 * { "type": "match",         "data": { "matchedNames": [...], ... } }
 * { "type": "peer_location", "data": { "userId", "latitude", ... } }
 * { "type": "peer_location_revoked", "data": { "userId" } }}</pre>
 *
 * @param <T> type of the {@code data} payload
 */
public record WsEnvelope<T>(String type, T data) {
}
