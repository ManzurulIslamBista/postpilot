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

/// What the screen can offer next to a network error, when the failure has a known way out (the web version only).
enum NetworkHelp {
  /// The browser's opaque network error with the CORS proxy off: the server may simply not allow web pages.
  corsBlocked,

  /// The CORS proxy was on and could not be used (not running, wrong token, a page it does not allow).
  corsProxy,
}

final class NetworkException extends AppException {
  final NetworkErrorKind kind;

  /// One line saying what went wrong and what to do about it ("Couldn't find
  /// the server ..."), when the client could tell; [message] keeps the
  /// technical detail. Never holds a secret: it names the host, not the URL.
  final String? summary;

  /// The action that fits this failure, when there is one.
  final NetworkHelp? help;

  const NetworkException(super.message, {this.kind = NetworkErrorKind.other, this.summary, this.help});
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
