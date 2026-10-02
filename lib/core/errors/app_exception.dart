sealed class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => message;
}

final class NotFoundException extends AppException {
  const NotFoundException(super.message);
}

enum NetworkErrorKind { timeout, connectionError, badResponse, cancelled, other }

final class NetworkException extends AppException {
  final NetworkErrorKind kind;
  const NetworkException(super.message, {this.kind = NetworkErrorKind.other});
}

final class InvalidUrlException extends AppException {
  const InvalidUrlException(super.message);
}

/// A request that cannot be built as configured (for example malformed JSON in
/// GraphQL variables or a JWT payload); [message] says what to fix and is safe
/// to show to the user as is.
final class InvalidRequestException extends AppException {
  const InvalidRequestException(super.message);
}

final class ImportException extends AppException {
  const ImportException(super.message);
}
