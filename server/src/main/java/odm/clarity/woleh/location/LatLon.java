package odm.clarity.woleh.location;

/**
 * Immutable WGS84-like latitude/longitude in decimal degrees (same convention as location publish).
 */
public record LatLon(double latitude, double longitude) {
}
