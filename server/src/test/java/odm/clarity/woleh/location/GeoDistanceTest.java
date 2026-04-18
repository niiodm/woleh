package odm.clarity.woleh.location;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.data.Offset.offset;

import org.junit.jupiter.api.Test;

class GeoDistanceTest {

	/** Identical points → zero length (reference: definition of metric). */
	@Test
	void samePoint_isZero() {
		double d = GeoDistance.haversineMeters(5.6037, -0.187, 5.6037, -0.187);
		assertThat(d).isZero();
	}

	/**
	 * Short east-west segment on the equator: 0.001° longitude at lat 0 ≈ (π/180) × R × 0.001 meters
	 * with R = 6_371_000 (reference: independent Haversine check ~111.195 m).
	 */
	@Test
	void equator_oneThousandthDegreeLongitude_isAbout111meters() {
		double d = GeoDistance.haversineMeters(0.0, 0.0, 0.0, 0.001);
		assertThat(d).isCloseTo(111.19493, offset(0.0001));
	}

	/**
	 * London–Paris great-circle distance (reference: WGS84-like degrees, independent Haversine
	 * ~342.8 km; not road distance).
	 */
	@Test
	void londonToParis_isAbout343km() {
		double latLon = 51.5007;
		double lonLon = -0.1246;
		double latPar = 48.8566;
		double lonPar = 2.3522;
		double d = GeoDistance.haversineMeters(latLon, lonLon, latPar, lonPar);
		assertThat(d).isCloseTo(342_806.53, offset(0.05));
	}
}
