package odm.clarity.woleh.location;

/**
 * Great-circle distance on a sphere (Haversine). Suitable for peer proximity ordering;
 * not for geodesy-grade surveying.
 */
public final class GeoDistance {

	/** Mean Earth radius (meters), common approximation for Haversine. */
	private static final double EARTH_MEAN_RADIUS_METERS = 6_371_000.0;

	private GeoDistance() {
	}

	/**
	 * Returns the distance between two WGS84-like (lat, lon) degrees on the spheroid,
	 * in meters.
	 */
	public static double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
		double phi1 = Math.toRadians(lat1);
		double phi2 = Math.toRadians(lat2);
		double deltaPhi = Math.toRadians(lat2 - lat1);
		double deltaLambda = Math.toRadians(lon2 - lon1);

		double sinHalfDPhi = Math.sin(deltaPhi / 2.0);
		double sinHalfDLambda = Math.sin(deltaLambda / 2.0);
		double a = sinHalfDPhi * sinHalfDPhi
				+ Math.cos(phi1) * Math.cos(phi2) * sinHalfDLambda * sinHalfDLambda;
		// Guard sqrt for a slightly > 1 from floating-point noise at antipodes.
		a = Math.min(1.0, Math.max(0.0, a));
		double c = 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a));
		return EARTH_MEAN_RADIUS_METERS * c;
	}
}
