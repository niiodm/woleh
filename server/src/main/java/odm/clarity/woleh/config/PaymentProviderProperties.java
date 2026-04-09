package odm.clarity.woleh.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Payment provider configuration ({@code woleh.payment.*}).
 *
 * <p>{@code baseUrl} is used by {@code StubPaymentProviderAdapter} to build the local
 * checkout URL in dev/test. Real provider credentials (API key, secret, webhook secret)
 * are added here when integrating a production provider.
 */
@ConfigurationProperties(prefix = "woleh.payment")
public record PaymentProviderProperties(String baseUrl) {

	public PaymentProviderProperties {
		if (baseUrl == null) baseUrl = "http://localhost:8080";
	}
}
