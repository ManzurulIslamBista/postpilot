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

final class ImportException extends AppException {
  const ImportException(super.message);
}
