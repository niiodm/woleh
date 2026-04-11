package odm.clarity.woleh.sms;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Normalizes phone numbers to NALO SMS format (Ghana: {@code 233XXXXXXXX}), matching bus_finder.
 *
 * <p>NALO expects Ghana numbers as country code + national digits without a leading {@code 0}.
 */
public final class PhoneNumberUtil {

	private static final Logger log = LoggerFactory.getLogger(PhoneNumberUtil.class);

	private static final String GHANA_COUNTRY_CODE = "233";
	private static final int GHANA_NATIONAL_NUMBER_LENGTH = 9;

	private PhoneNumberUtil() {}

	public static String normalizeToNaloFormat(String phoneNumber) {
		if (phoneNumber == null || phoneNumber.trim().isEmpty()) {
			log.warn("Empty phone number provided for normalization");
			return phoneNumber;
		}

		String cleaned = phoneNumber.replaceAll("[^0-9]", "");

		if (cleaned.isEmpty()) {
			log.warn("No digits found in phone number: {}", phoneNumber);
			return phoneNumber;
		}

		if (cleaned.startsWith(GHANA_COUNTRY_CODE)) {
			String number = cleaned.substring(GHANA_COUNTRY_CODE.length());
			if (number.startsWith("0")) {
				number = number.substring(1);
			}
			if (number.length() == GHANA_NATIONAL_NUMBER_LENGTH) {
				String normalized = GHANA_COUNTRY_CODE + number;
				log.debug("Normalized phone number: {} → {}", phoneNumber, normalized);
				return normalized;
			}
		}

		if (cleaned.startsWith("0") && cleaned.length() == GHANA_NATIONAL_NUMBER_LENGTH + 1) {
			String number = cleaned.substring(1);
			String normalized = GHANA_COUNTRY_CODE + number;
			log.debug("Normalized phone number: {} → {}", phoneNumber, normalized);
			return normalized;
		}

		if (cleaned.length() == GHANA_NATIONAL_NUMBER_LENGTH && !cleaned.startsWith("0")) {
			String normalized = GHANA_COUNTRY_CODE + cleaned;
			log.debug("Normalized phone number: {} → {}", phoneNumber, normalized);
			return normalized;
		}

		if (cleaned.length() == GHANA_COUNTRY_CODE.length() + GHANA_NATIONAL_NUMBER_LENGTH) {
			log.debug("Phone number appears to be in correct format: {}", cleaned);
			return cleaned;
		}

		log.warn("Unable to normalize phone number: {} (cleaned: {}, length: {})",
				phoneNumber, cleaned, cleaned.length());
		return cleaned;
	}

	public static boolean isValidNaloFormat(String phoneNumber) {
		if (phoneNumber == null || phoneNumber.isEmpty()) {
			return false;
		}
		return phoneNumber.matches("^233\\d{9}$");
	}
}
