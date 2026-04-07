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
