sealed class AppError implements Exception {
  const AppError(this.message);

  final String message;
}

final class UnauthorizedError extends AppError {
  const UnauthorizedError([super.message = 'Unauthorized']);
}

final class ForbiddenError extends AppError {
  const ForbiddenError([super.message = 'Forbidden']);
}

final class RateLimitedError extends AppError {
  const RateLimitedError([super.message = 'Too many requests']);
}

final class ServerError extends AppError {
  const ServerError([super.message = 'Server error']);
}

final class NetworkError extends AppError {
  const NetworkError([super.message = 'No connection']);
}

final class UnknownError extends AppError {
  const UnknownError([super.message = 'Unknown error']);
}

/// No connectivity and no cached copy available for the requested resource.
final class OfflineError extends AppError {
  const OfflineError([
    super.message = 'No saved data available while offline.',
  ]);
}

/// A place name failed server-side validation (HTTP 400 `VALIDATION_ERROR`).
/// Covers: empty-after-trim, over-200-code-points, duplicate normalized name
/// in a broadcast list.
final class PlaceValidationError extends AppError {
  const PlaceValidationError([super.message = 'Invalid place name']);
}

/// The user has exceeded their place-list limit (HTTP 403 `OVER_LIMIT`).
/// Distinct from [ForbiddenError] which covers missing permissions.
final class PlaceLimitError extends AppError {
  const PlaceLimitError([super.message = 'Place list limit exceeded']);
}

/// Shared saved list not found (HTTP 404) or invalid share token.
final class SavedListNotFoundError extends AppError {
  const SavedListNotFoundError([super.message = 'Saved list not found']);
}
