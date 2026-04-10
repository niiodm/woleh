package odm.clarity.woleh.ws;

/**
 * Payload for {@code peer_location_revoked}: a matched peer stopped location sharing
 * (MAP_LIVE_LOCATION_PLAN §3.4). Clients should remove that {@code userId} from the map.
 */
public record PeerLocationRevokedEvent(String userId) {
}
