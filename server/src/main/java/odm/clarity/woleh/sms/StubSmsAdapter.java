package odm.clarity.woleh.sms;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * Development / default SMS implementation: no real SMS is sent (same role as bus_finder {@code MockSmsService}).
 *
 * <p>Active when {@code sms.provider=mock} or the property is unset. OTP logging is handled by
 * {@code OtpService} when {@code woleh.otp.dev-log-otp=true}.
 */
@Component
@ConditionalOnProperty(name = "sms.provider", havingValue = "mock", matchIfMissing = true)
public class StubSmsAdapter implements SmsAdapter {

	private static final Logger log = LoggerFactory.getLogger(StubSmsAdapter.class);

	@Override
	public void sendOtp(String phoneE164, String otp) {
		log.info("[StubSmsAdapter] OTP send skipped for {} — replace with real adapter before production", phoneE164);
	}
}
