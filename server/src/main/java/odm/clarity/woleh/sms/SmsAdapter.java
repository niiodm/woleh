package odm.clarity.woleh.sms;

/**
 * Port for sending SMS messages.
 *
 * <p>Default: {@link StubSmsAdapter} ({@code sms.provider=mock}). Production (bus_finder parity):
 * {@link NaloSmsAdapter} with {@code sms.provider=nalo}.
 */
public interface SmsAdapter {

	/**
	 * Dispatch the given OTP to {@code phoneE164}.
	 * Implementations must not store or log {@code otp} in production-level logging.
	 */
	void sendOtp(String phoneE164, String otp);
}
