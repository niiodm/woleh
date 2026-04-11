package odm.clarity.woleh.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

/**
 * HTTP client for SMS provider APIs (timeouts match bus_finder defaults).
 */
@Configuration
public class SmsHttpClientConfig {

	private static final Logger log = LoggerFactory.getLogger(SmsHttpClientConfig.class);

	@Value("${sms.http.connect-timeout:5000}")
	private int connectTimeoutMs;

	@Value("${sms.http.read-timeout:10000}")
	private int readTimeoutMs;

	@Bean
	public RestTemplate smsRestTemplate() {
		ClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
		((SimpleClientHttpRequestFactory) factory).setConnectTimeout(connectTimeoutMs);
		((SimpleClientHttpRequestFactory) factory).setReadTimeout(readTimeoutMs);
		RestTemplate restTemplate = new RestTemplate(factory);
		log.debug("SMS RestTemplate: connect {}ms, read {}ms", connectTimeoutMs, readTimeoutMs);
		return restTemplate;
	}
}
