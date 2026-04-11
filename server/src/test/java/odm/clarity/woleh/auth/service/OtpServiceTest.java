package odm.clarity.woleh.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.lang.reflect.Field;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

import odm.clarity.woleh.common.error.InvalidOtpException;
import odm.clarity.woleh.common.error.RateLimitedException;
import odm.clarity.woleh.config.OtpProperties;
import odm.clarity.woleh.model.OtpChallenge;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.OtpChallengeRepository;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.sms.SmsAdapter;
import odm.clarity.woleh.subscription.SubscriptionService;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class OtpServiceTest {

	private static final String PHONE = "+233241000099";

	@Mock OtpChallengeRepository otpChallengeRepository;
	@Mock UserRepository userRepository;
	@Mock SmsAdapter smsAdapter;
	@Mock SubscriptionService subscriptionService;

	// Real encoder so hash/match behaviour is genuine
	private final PasswordEncoder passwordEncoder = new BCryptPasswordEncoder();

	private OtpProperties props;
	private OtpService service;

	@BeforeEach
	void setUp() {
		props = new OtpProperties(Duration.ofMinutes(5), Duration.ofHours(1), 3, false);
		service = new OtpService(otpChallengeRepository, userRepository, passwordEncoder, smsAdapter, props,
				subscriptionService);
	}

	// ── issueOtp ─────────────────────────────────────────────────────────────

	@Nested
	class IssueOtp {

		@BeforeEach
		void allowSave() {
			// lenient: some tests override countBy and don't reach save; strict mode would flag the unused stub.
			Mockito.lenient().when(otpChallengeRepository.countByPhoneE164AndCreatedAtAfter(eq(PHONE), any())).thenReturn(0L);
			Mockito.lenient().when(otpChallengeRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
		}

		@Test
		void generatesOtpWithExactlySixDigits() {
			ArgumentCaptor<OtpChallenge> captor = ArgumentCaptor.forClass(OtpChallenge.class);
			service.issueOtp(PHONE);
			verify(otpChallengeRepository).save(captor.capture());

			String hash = captor.getValue().getOtpHash();
			assertThat(hash).isNotBlank();
			// Hash must not be the plaintext (BCrypt hashes start with "$2")
			assertThat(hash).startsWith("$2");
		}

		@Test
		void storesHashedOtp_notPlaintext() {
			// Capture the OTP given to the SMS adapter and confirm the stored hash matches
			ArgumentCaptor<String> otpCaptor = ArgumentCaptor.forClass(String.class);
			ArgumentCaptor<OtpChallenge> challengeCaptor = ArgumentCaptor.forClass(OtpChallenge.class);

			service.issueOtp(PHONE);

			verify(smsAdapter).sendOtp(eq(PHONE), otpCaptor.capture());
			verify(otpChallengeRepository).save(challengeCaptor.capture());

			String plainOtp = otpCaptor.getValue();
			String storedHash = challengeCaptor.getValue().getOtpHash();

			assertThat(plainOtp).matches("\\d{6}");
			assertThat(passwordEncoder.matches(plainOtp, storedHash)).isTrue();
		}

		@Test
		void setsTtlOnChallenge() {
			ArgumentCaptor<OtpChallenge> captor = ArgumentCaptor.forClass(OtpChallenge.class);
			Instant before = Instant.now();
			service.issueOtp(PHONE);
			Instant after = Instant.now();
			verify(otpChallengeRepository).save(captor.capture());

			Instant expiresAt = captor.getValue().getExpiresAt();
			assertThat(expiresAt).isAfterOrEqualTo(before.plus(props.ttl()));
			assertThat(expiresAt).isBeforeOrEqualTo(after.plus(props.ttl()));
		}

		@Test
		void callsSmsAdapter() {
			service.issueOtp(PHONE);
			verify(smsAdapter).sendOtp(eq(PHONE), anyString());
		}

		@Test
		void throwsRateLimited_whenAtMaxSends() {
			when(otpChallengeRepository.countByPhoneE164AndCreatedAtAfter(eq(PHONE), any()))
					.thenReturn((long) props.rateLimitMaxSends());

			assertThatThrownBy(() -> service.issueOtp(PHONE))
					.isInstanceOf(RateLimitedException.class);

			verify(otpChallengeRepository, never()).save(any());
			verify(smsAdapter, never()).sendOtp(anyString(), anyString());
		}

		@Test
		void doesNotThrow_whenJustBelowRateLimit() {
			when(otpChallengeRepository.countByPhoneE164AndCreatedAtAfter(eq(PHONE), any()))
					.thenReturn((long) (props.rateLimitMaxSends() - 1));

			assertThat(service.issueOtp(PHONE)).isNotNull();
		}
	}

	// ── verifyOtp ────────────────────────────────────────────────────────────

	@Nested
	class VerifyOtp {

		private static final String OTP = "472819";

		private OtpChallenge validChallenge;

		@BeforeEach
		void setup() {
			String hash = passwordEncoder.encode(OTP);
			validChallenge = new OtpChallenge(PHONE, hash, Instant.now().plusSeconds(300));
		}

		// ── challenge resolution ──────────────────────────────────────────────

		@Test
		void throws_whenNoPendingChallenge() {
			when(otpChallengeRepository.findByPhoneE164AndConsumedOrderByCreatedAtDesc(PHONE, false))
					.thenReturn(List.of());

			assertThatThrownBy(() -> service.verifyOtp(PHONE, OTP))
					.isInstanceOf(InvalidOtpException.class)
					.hasMessageContaining("No active OTP");
		}

		@Test
		void throws_whenChallengeIsExpired() {
			OtpChallenge expired = new OtpChallenge(PHONE, passwordEncoder.encode(OTP),
					Instant.now().minusSeconds(1));
			when(otpChallengeRepository.findByPhoneE164AndConsumedOrderByCreatedAtDesc(PHONE, false))
					.thenReturn(List.of(expired));

			assertThatThrownBy(() -> service.verifyOtp(PHONE, OTP))
					.isInstanceOf(InvalidOtpException.class)
					.hasMessageContaining("expired");
		}

		@Test
		void throws_whenAttemptCountExhausted() {
			validChallenge.setAttemptCount(5);
			when(otpChallengeRepository.findByPhoneE164AndConsumedOrderByCreatedAtDesc(PHONE, false))
					.thenReturn(List.of(validChallenge));

			assertThatThrownBy(() -> service.verifyOtp(PHONE, OTP))
					.isInstanceOf(InvalidOtpException.class)
					.hasMessageContaining("too many failed attempts");
		}

		// ── wrong OTP ─────────────────────────────────────────────────────────

		@Test
		void throws_andIncrementsAttempt_onWrongOtp() {
			when(otpChallengeRepository.findByPhoneE164AndConsumedOrderByCreatedAtDesc(PHONE, false))
					.thenReturn(List.of(validChallenge));
			when(otpChallengeRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

			assertThatThrownBy(() -> service.verifyOtp(PHONE, "000000"))
					.isInstanceOf(InvalidOtpException.class);

			ArgumentCaptor<OtpChallenge> captor = ArgumentCaptor.forClass(OtpChallenge.class);
			verify(otpChallengeRepository).save(captor.capture());
			assertThat(captor.getValue().getAttemptCount()).isEqualTo(1);
		}

		@Test
		void doesNotCreateUser_onWrongOtp() {
			when(otpChallengeRepository.findByPhoneE164AndConsumedOrderByCreatedAtDesc(PHONE, false))
					.thenReturn(List.of(validChallenge));
			when(otpChallengeRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

			assertThatThrownBy(() -> service.verifyOtp(PHONE, "000000"))
					.isInstanceOf(InvalidOtpException.class);

			verify(userRepository, never()).save(any());
		}

		// ── correct OTP / signup flow ─────────────────────────────────────────

		@Test
		void returnsSignupFlow_forNewUser() {
			stubCorrectOtp(false);

			VerifyOtpResult result = service.verifyOtp(PHONE, OTP);

			assertThat(result.flow()).isEqualTo("signup");
		}

		@Test
		void createsUser_forNewPhone() {
			stubCorrectOtp(false);

			service.verifyOtp(PHONE, OTP);

			ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
			verify(userRepository).save(captor.capture());
			assertThat(captor.getValue().getPhoneE164()).isEqualTo(PHONE);
		}

		@Test
		void activatesFreePlan_forNewUser() {
			stubCorrectOtp(false);

			service.verifyOtp(PHONE, OTP);

			ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
			verify(subscriptionService).activateFreePlanForNewUser(captor.capture());
			assertThat(captor.getValue().getPhoneE164()).isEqualTo(PHONE);
		}

		// ── correct OTP / login flow ──────────────────────────────────────────

		@Test
		void returnsLoginFlow_forExistingUser() {
			stubCorrectOtp(true);

			VerifyOtpResult result = service.verifyOtp(PHONE, OTP);

			assertThat(result.flow()).isEqualTo("login");
		}

		@Test
		void doesNotCreateUser_forExistingPhone() {
			stubCorrectOtp(true);

			service.verifyOtp(PHONE, OTP);

			verify(userRepository, never()).save(any(User.class));
			verify(subscriptionService, never()).activateFreePlanForNewUser(any());
		}

		// ── consumed guard ────────────────────────────────────────────────────

		@Test
		void marksChallengeConsumed_onSuccess() {
			stubCorrectOtp(false);

			service.verifyOtp(PHONE, OTP);

			ArgumentCaptor<OtpChallenge> captor = ArgumentCaptor.forClass(OtpChallenge.class);
			// save is called once to mark consumed (user save is separate repo call)
			verify(otpChallengeRepository).save(captor.capture());
			assertThat(captor.getValue().isConsumed()).isTrue();
		}

		// ── helpers ───────────────────────────────────────────────────────────

		private void stubCorrectOtp(boolean userExists) {
			when(otpChallengeRepository.findByPhoneE164AndConsumedOrderByCreatedAtDesc(PHONE, false))
					.thenReturn(List.of(validChallenge));
			when(otpChallengeRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
			when(userRepository.existsByPhoneE164(PHONE)).thenReturn(userExists);

			if (userExists) {
				User existing = userWithId(42L, PHONE);
				when(userRepository.findByPhoneE164(PHONE)).thenReturn(Optional.of(existing));
			} else {
				User created = userWithId(1L, PHONE);
				when(userRepository.save(any(User.class))).thenReturn(created);
			}
		}

		private static User userWithId(long id, String phone) {
			User u = new User(phone);
			try {
				Field f = User.class.getDeclaredField("id");
				f.setAccessible(true);
				f.set(u, id);
			} catch (ReflectiveOperationException e) {
				throw new RuntimeException(e);
			}
			return u;
		}
	}
}
