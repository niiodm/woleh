package odm.clarity.woleh.places;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import odm.clarity.woleh.common.error.PlaceLimitExceededException;
import odm.clarity.woleh.common.error.PlaceNameValidationException;
import odm.clarity.woleh.common.error.PermissionDeniedException;
import odm.clarity.woleh.common.error.SavedPlaceListNotFoundException;
import odm.clarity.woleh.common.error.UserNotFoundException;
import odm.clarity.woleh.model.User;
import odm.clarity.woleh.model.UserSavedPlaceList;
import odm.clarity.woleh.places.dto.SavedPlaceListDetailResponse;
import odm.clarity.woleh.places.dto.SavedPlaceListPublicResponse;
import odm.clarity.woleh.places.dto.SavedPlaceListSummaryResponse;
import odm.clarity.woleh.places.util.PlaceNameNormalizer;
import odm.clarity.woleh.repository.UserRepository;
import odm.clarity.woleh.repository.UserSavedPlaceListRepository;
import odm.clarity.woleh.subscription.EntitlementService;
import odm.clarity.woleh.subscription.Entitlements;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * CRUD for user saved place list templates (not live watch/broadcast lists).
 * Name rules match watch lists: validate + dedupe by normalized form.
 */
@Service
@Transactional
public class SavedPlaceListService {

	private static final String PERM_WATCH = "woleh.place.watch";
	private static final String PERM_BROADCAST = "woleh.place.broadcast";

	private static final int SHARE_TOKEN_BYTES = 24;
	private static final int MAX_TOKEN_ATTEMPTS = 8;

	private final UserSavedPlaceListRepository savedListRepository;
	private final UserRepository userRepository;
	private final EntitlementService entitlementService;
	private final PlaceNameNormalizer normalizer;
	private final SecureRandom secureRandom = new SecureRandom();

	public SavedPlaceListService(
			UserSavedPlaceListRepository savedListRepository,
			UserRepository userRepository,
			EntitlementService entitlementService,
			PlaceNameNormalizer normalizer) {
		this.savedListRepository = savedListRepository;
		this.userRepository = userRepository;
		this.entitlementService = entitlementService;
		this.normalizer = normalizer;
	}

	@Transactional(readOnly = true)
	public List<SavedPlaceListSummaryResponse> listSummaries(Long userId) {
		requireWatchOrBroadcast(entitlementService.computeEntitlements(userId));
		return savedListRepository.findByUser_IdOrderByUpdatedAtDesc(userId).stream()
				.map(l -> new SavedPlaceListSummaryResponse(
						l.getId(),
						l.getTitle(),
						l.getDisplayNames().size(),
						l.getShareToken(),
						l.getUpdatedAt()))
				.toList();
	}

	@Transactional(readOnly = true)
	public SavedPlaceListDetailResponse getOwned(Long userId, long listId) {
		requireWatchOrBroadcast(entitlementService.computeEntitlements(userId));
		UserSavedPlaceList list = savedListRepository.findByIdAndUser_Id(listId, userId)
				.orElseThrow(SavedPlaceListNotFoundException::new);
		return toDetail(list);
	}

	public SavedPlaceListDetailResponse create(Long userId, String title, List<String> rawNames) {
		Entitlements ent = requireWatchOrBroadcast(entitlementService.computeEntitlements(userId));

		long count = savedListRepository.countByUser_Id(userId);
		if (count >= ent.savedPlaceListMax()) {
			throw new PlaceLimitExceededException("saved_place_lists", ent.savedPlaceListMax());
		}

		DedupeResult deduped = validateAndDedupe(rawNames);
		int nameCap = templateNameCap(ent);
		if (deduped.displayNames().size() > nameCap) {
			throw new PlaceLimitExceededException("saved_list_places", nameCap);
		}

		User user = userRepository.findById(userId)
				.orElseThrow(() -> new UserNotFoundException(userId));

		String token = allocateUniqueShareToken();
		UserSavedPlaceList row = new UserSavedPlaceList(
				user, title, token, deduped.displayNames(), deduped.normalizedNames());
		savedListRepository.save(row);
		return toDetail(row);
	}

	public SavedPlaceListDetailResponse replace(Long userId, long listId, String title, List<String> rawNames) {
		Entitlements ent = requireWatchOrBroadcast(entitlementService.computeEntitlements(userId));
		UserSavedPlaceList list = savedListRepository.findByIdAndUser_Id(listId, userId)
				.orElseThrow(SavedPlaceListNotFoundException::new);

		DedupeResult deduped = validateAndDedupe(rawNames);
		int nameCap = templateNameCap(ent);
		if (deduped.displayNames().size() > nameCap) {
			throw new PlaceLimitExceededException("saved_list_places", nameCap);
		}

		list.setTitle(title);
		list.setDisplayNames(deduped.displayNames());
		list.setNormalizedNames(deduped.normalizedNames());
		savedListRepository.save(list);
		return toDetail(list);
	}

	public void delete(Long userId, long listId) {
		requireWatchOrBroadcast(entitlementService.computeEntitlements(userId));
		UserSavedPlaceList list = savedListRepository.findByIdAndUser_Id(listId, userId)
				.orElseThrow(SavedPlaceListNotFoundException::new);
		savedListRepository.delete(list);
	}

	@Transactional(readOnly = true)
	public SavedPlaceListPublicResponse getPublicByShareToken(String token) {
		if (token == null || token.isBlank()) {
			throw new SavedPlaceListNotFoundException();
		}
		UserSavedPlaceList list = savedListRepository.findByShareToken(token.trim())
				.orElseThrow(SavedPlaceListNotFoundException::new);
		return new SavedPlaceListPublicResponse(list.getTitle(), list.getDisplayNames());
	}

	private static SavedPlaceListDetailResponse toDetail(UserSavedPlaceList list) {
		return new SavedPlaceListDetailResponse(
				list.getId(),
				list.getTitle(),
				list.getDisplayNames(),
				list.getShareToken(),
				list.getCreatedAt(),
				list.getUpdatedAt());
	}

	private String allocateUniqueShareToken() {
		for (int i = 0; i < MAX_TOKEN_ATTEMPTS; i++) {
			String candidate = newShareToken();
			if (!savedListRepository.existsByShareToken(candidate)) {
				return candidate;
			}
		}
		throw new IllegalStateException("Could not allocate unique share token");
	}

	private String newShareToken() {
		byte[] bytes = new byte[SHARE_TOKEN_BYTES];
		secureRandom.nextBytes(bytes);
		return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
	}

	private static int templateNameCap(Entitlements ent) {
		if (ent.permissions().contains(PERM_BROADCAST)) {
			return ent.placeBroadcastMax();
		}
		return ent.placeWatchMax();
	}

	private static Entitlements requireWatchOrBroadcast(Entitlements ent) {
		if (ent.permissions().contains(PERM_WATCH) || ent.permissions().contains(PERM_BROADCAST)) {
			return ent;
		}
		throw new PermissionDeniedException(PERM_WATCH + " or " + PERM_BROADCAST);
	}

	private DedupeResult validateAndDedupe(List<String> rawNames) {
		List<String> displayResult = new ArrayList<>();
		List<String> normalizedResult = new ArrayList<>();
		Set<String> seen = new LinkedHashSet<>();

		for (String raw : rawNames) {
			normalizer.validatePlaceName(raw);
			String norm = normalizer.normalize(raw);
			if (seen.add(norm)) {
				displayResult.add(raw);
				normalizedResult.add(norm);
			}
		}

		return new DedupeResult(displayResult, normalizedResult);
	}

	private record DedupeResult(List<String> displayNames, List<String> normalizedNames) {
	}
}
