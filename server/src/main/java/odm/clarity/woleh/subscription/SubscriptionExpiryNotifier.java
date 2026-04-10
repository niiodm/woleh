package odm.clarity.woleh.subscription;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import odm.clarity.woleh.model.Subscription;
import odm.clarity.woleh.model.SubscriptionStatus;
import odm.clarity.woleh.push.FcmService;
import odm.clarity.woleh.repository.SubscriptionRepository;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Daily reminder for subscriptions whose billing period ends within the next 24 hours.
 */
@Component
public class SubscriptionExpiryNotifier {

	private static final Logger log = LoggerFactory.getLogger(SubscriptionExpiryNotifier.class);

	private final SubscriptionRepository subscriptionRepository;
	private final FcmService fcmService;

	public SubscriptionExpiryNotifier(SubscriptionRepository subscriptionRepository, FcmService fcmService) {
		this.subscriptionRepository = subscriptionRepository;
		this.fcmService = fcmService;
	}

	/** Once per day at 08:00 UTC. */
	@Scheduled(cron = "0 0 8 * * *", zone = "UTC")
	public void notifyExpiringSubscriptions() {
		Instant now = Instant.now();
		Instant cutoff = now.plus(24, ChronoUnit.HOURS);
		List<Subscription> expiring = subscriptionRepository.findActiveExpiringBetween(
				SubscriptionStatus.ACTIVE, now, cutoff);
		if (expiring.isEmpty()) {
			return;
		}

		Set<Long> userIds = new HashSet<>();
		for (Subscription sub : expiring) {
			long userId = sub.getUser().getId();
			if (userIds.add(userId)) {
				log.debug("SubscriptionExpiryNotifier: notifying userId={} periodEnd={}", userId, sub.getCurrentPeriodEnd());
				fcmService.sendNotification(userId,
						"Subscription expiring soon",
						"Your plan expires tomorrow — renew to keep access.",
						Map.of("kind", "subscription_expiry"));
			}
		}
	}
}
