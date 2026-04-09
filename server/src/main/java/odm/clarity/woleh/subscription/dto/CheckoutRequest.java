package odm.clarity.woleh.subscription.dto;

import jakarta.validation.constraints.NotBlank;

/** Request body for {@code POST /api/v1/subscription/checkout} (API_CONTRACT.md §6.6). */
public record CheckoutRequest(@NotBlank String planId) {
}
