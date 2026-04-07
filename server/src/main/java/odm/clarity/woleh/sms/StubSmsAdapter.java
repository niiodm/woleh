package odm.clarity.woleh.sms;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Phase-0 stub: no real SMS is sent.
 * OTP logging is handled by {@code OtpService} when {@code woleh.otp.dev-log-otp=true}.
 */
@Component
public class StubSmsAdapter implements SmsAdapter {

	private static final Logger log = LoggerFactory.getLogger(StubSmsAdapter.class);

	@Override
	public void sendOtp(String phoneE164, String otp) {
		log.info("[StubSmsAdapter] OTP send skipped for {} — replace with real adapter before production", phoneE164);
	}
}
