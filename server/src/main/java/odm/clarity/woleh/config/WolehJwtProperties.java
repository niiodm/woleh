package odm.clarity.woleh.config;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * JWT signing and validation settings (access tokens). Used by auth in step 3.5+.
 */
@ConfigurationProperties(prefix = "woleh.jwt")
public record WolehJwtProperties(
		@DefaultValue("woleh") String issuer,
		@DefaultValue("PT24H") Duration accessTokenTtl,
		String secret) {
}
