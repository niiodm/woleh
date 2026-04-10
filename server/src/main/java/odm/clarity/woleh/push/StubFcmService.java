package odm.clarity.woleh.push;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.stereotype.Service;

/**
 * Default no-op FCM implementation (logs payloads). Active whenever {@link RealFcmService} is not.
 */
@Service
@ConditionalOnMissingBean(RealFcmService.class)
public class StubFcmService implements FcmService {

	private static final Logger log = LoggerFactory.getLogger(StubFcmService.class);

	@Override
	public void sendNotification(long userId, String title, String body, Map<String, String> data) {
		log.info("StubFcmService.sendNotification userId={} title={} body={} data={}",
				userId, title, body, data);
	}
}
