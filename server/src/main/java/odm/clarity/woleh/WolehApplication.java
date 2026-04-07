package odm.clarity.woleh;

import odm.clarity.woleh.config.WolehJwtProperties;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

@SpringBootApplication
@EnableConfigurationProperties(WolehJwtProperties.class)
public class WolehApplication {

	public static void main(String[] args) {
		SpringApplication.run(WolehApplication.class, args);
	}

}
