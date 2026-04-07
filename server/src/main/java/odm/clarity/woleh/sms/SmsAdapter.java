package odm.clarity.woleh.sms;

/**
 * Port for sending SMS messages.
 * Swap the {@link StubSmsAdapter} for a real implementation (Twilio, AWS SNS, etc.) in production.
 */
public interface SmsAdapter {

	/**
	 * Dispatch the given OTP to {@code phoneE164}.
	 * Implementations must not store or log {@code otp} in production-level logging.
	 */
	void sendOtp(String phoneE164, String otp);
}
