package odm.clarity.woleh.push;

import java.util.Map;

/**
 * Sends push notifications to a user's registered device tokens (FCM).
 */
public interface FcmService {

	void sendNotification(long userId, String title, String body, Map<String, String> data);
}
