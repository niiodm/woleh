package odm.clarity.woleh.places;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.places.dto.SavedPlaceListPublicResponse;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/public/saved-place-lists")
public class PublicSavedPlaceListController {

	private final SavedPlaceListService savedPlaceListService;

	public PublicSavedPlaceListController(SavedPlaceListService savedPlaceListService) {
		this.savedPlaceListService = savedPlaceListService;
	}

	@GetMapping("/{token}")
	ResponseEntity<ApiEnvelope<SavedPlaceListPublicResponse>> getByToken(
			@PathVariable("token") String token) {
		return ResponseEntity.ok(ApiEnvelope.success("OK", savedPlaceListService.getPublicByShareToken(token)));
	}
}
