import '../../../../core/errors/app_exception.dart';

/// Short, human-readable text for the exceptions a send can throw: the same
/// wording the local request builder shows. The HTTP client wraps every network
/// failure in a [NetworkException] with a [NetworkErrorKind]; an unsendable URL
/// is an [InvalidUrlException]; one `Uri.parse` can't read surfaces as a
/// [FormatException] before the request ever reaches the client.
abstract final class SendErrorMessage {
  static String of(Object error) {
    if (error is NetworkException) {
      return switch (error.kind) {
        NetworkErrorKind.timeout => 'Request timed out',
        NetworkErrorKind.connectionError => "Couldn't reach the server — check the URL and your connection",
        NetworkErrorKind.badResponse => 'The server returned an unexpected response',
        NetworkErrorKind.cancelled => 'Request cancelled',
        NetworkErrorKind.other => 'Something went wrong sending this request',
      };
    }
    if (error is InvalidUrlException) {
      return "That URL isn't valid — it needs a host, e.g. https://api.example.com/users";
    }
    if (error is FormatException) {
      return "Couldn't reach the server — check the URL and your connection";
    }
    return 'Something went wrong sending this request';
  }
}
