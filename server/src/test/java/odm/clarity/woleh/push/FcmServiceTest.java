package odm.clarity.woleh.push;

import java.util.Map;

import org.junit.jupiter.api.Test;

class FcmServiceTest {

	@Test
	void stubFcmService_doesNotThrow() {
		FcmService fcm = new StubFcmService();
		fcm.sendNotification(42L, "t", "b", Map.of("k", "v"));
	}
}
