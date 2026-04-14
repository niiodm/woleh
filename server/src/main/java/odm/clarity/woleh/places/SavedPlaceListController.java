package odm.clarity.woleh.places;

import java.util.List;

import jakarta.validation.Valid;

import odm.clarity.woleh.api.dto.ApiEnvelope;
import odm.clarity.woleh.places.dto.SavedPlaceListCreateRequest;
import odm.clarity.woleh.places.dto.SavedPlaceListDetailResponse;
import odm.clarity.woleh.places.dto.SavedPlaceListSummaryResponse;
import odm.clarity.woleh.places.dto.SavedPlaceListUpdateRequest;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/me/saved-place-lists")
public class SavedPlaceListController {

	private final SavedPlaceListService savedPlaceListService;

	public SavedPlaceListController(SavedPlaceListService savedPlaceListService) {
		this.savedPlaceListService = savedPlaceListService;
	}

	@GetMapping
	ResponseEntity<ApiEnvelope<List<SavedPlaceListSummaryResponse>>> list(
			@AuthenticationPrincipal Long userId) {
		return ResponseEntity.ok(ApiEnvelope.success("OK", savedPlaceListService.listSummaries(userId)));
	}

	@PostMapping
	ResponseEntity<ApiEnvelope<SavedPlaceListDetailResponse>> create(
			@AuthenticationPrincipal Long userId,
			@RequestBody @Valid SavedPlaceListCreateRequest request) {
		return ResponseEntity.ok(ApiEnvelope.success("Saved place list created",
				savedPlaceListService.create(userId, request.title(), request.names())));
	}

	@GetMapping("/{id}")
	ResponseEntity<ApiEnvelope<SavedPlaceListDetailResponse>> get(
			@AuthenticationPrincipal Long userId,
			@PathVariable("id") long id) {
		return ResponseEntity.ok(ApiEnvelope.success("OK", savedPlaceListService.getOwned(userId, id)));
	}

	@PutMapping("/{id}")
	ResponseEntity<ApiEnvelope<SavedPlaceListDetailResponse>> replace(
			@AuthenticationPrincipal Long userId,
			@PathVariable("id") long id,
			@RequestBody @Valid SavedPlaceListUpdateRequest request) {
		return ResponseEntity.ok(ApiEnvelope.success("Saved place list updated",
				savedPlaceListService.replace(userId, id, request.title(), request.names())));
	}

	@DeleteMapping("/{id}")
	ResponseEntity<ApiEnvelope<Void>> delete(
			@AuthenticationPrincipal Long userId,
			@PathVariable("id") long id) {
		savedPlaceListService.delete(userId, id);
		return ResponseEntity.ok(ApiEnvelope.success("Saved place list deleted", null));
	}
}
