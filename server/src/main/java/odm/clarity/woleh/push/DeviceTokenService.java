package odm.clarity.woleh.push;

import java.time.Instant;

import odm.clarity.woleh.common.error.UserNotFoundException;
import odm.clarity.woleh.model.DevicePlatform;
import odm.clarity.woleh.model.DeviceToken;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.repository.DeviceTokenRepository;
import odm.clarity.woleh.repository.UserRepository;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeviceTokenService {

	private final UserRepository userRepository;
	private final DeviceTokenRepository deviceTokenRepository;

	public DeviceTokenService(UserRepository userRepository, DeviceTokenRepository deviceTokenRepository) {
		this.userRepository = userRepository;
		this.deviceTokenRepository = deviceTokenRepository;
	}

	@Transactional
	public void upsert(Long userId, String token, DevicePlatform platform) {
		User user = userRepository.findById(userId).orElseThrow(() -> new UserNotFoundException(userId));
		Instant now = Instant.now();
		deviceTokenRepository.findByUser_IdAndToken(userId, token).ifPresentOrElse(
				dt -> {
					dt.setUpdatedAt(now);
					deviceTokenRepository.save(dt);
				},
				() -> deviceTokenRepository.save(new DeviceToken(user, token, platform)));
	}

	@Transactional
	public void deleteByUserAndToken(Long userId, String token) {
		deviceTokenRepository.deleteByUser_IdAndToken(userId, token);
	}
}
