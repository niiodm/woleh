package odm.clarity.woleh.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class WolehJwtPropertiesTest {

	@Autowired
	private WolehJwtProperties jwtProperties;

	@Test
	void bindsIssuerAndTtl() {
		assertThat(jwtProperties.issuer()).isEqualTo("woleh");
		assertThat(jwtProperties.accessTokenTtl().toHours()).isEqualTo(24);
		assertThat(jwtProperties.secret()).isNotBlank();
	}
}
