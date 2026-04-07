package odm.clarity.woleh.api;

import java.util.Map;

import odm.clarity.woleh.api.dto.ApiEnvelope;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Session / profile (full contract in step 3.6).
 */
@RestController
@RequestMapping("/api/v1")
public class MeController {

	@GetMapping("/me")
	public ApiEnvelope<Map<String, String>> me(@AuthenticationPrincipal Long userId) {
		return ApiEnvelope.success("OK", Map.of("userId", String.valueOf(userId)));
	}
}
