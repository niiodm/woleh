package odm.clarity.woleh;

import odm.clarity.woleh.config.OtpProperties;
import odm.clarity.woleh.config.PaymentProviderProperties;
import odm.clarity.woleh.config.RateLimitProperties;
import odm.clarity.woleh.config.WolehJwtProperties;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
@EnableConfigurationProperties({ WolehJwtProperties.class, OtpProperties.class, PaymentProviderProperties.class, RateLimitProperties.class })
public class WolehApplication {

	public static void main(String[] args) {
		SpringApplication.run(WolehApplication.class, args);
	}

}
