// Pure Dart (no Flutter): the app, the command line and the MCP server decide re-logins with the same rules.
import '../../../../core/enums/http_method.dart';
import '../../../defaults/domain/entities/defaults_chain.dart';
import '../entities/relogin_config.dart';

/// A request that could be the login request, with where it sits.
final class ReloginCandidate<T> {
  /// The folders above it, joined by `/`; empty at the top of the collection.
  final String folderPath;
  final String name;
  final HttpMethod method;

  /// Whatever the caller needs to run it (a request summary, a backup entry).
  final T value;

  const ReloginCandidate({required this.folderPath, required this.name, required this.method, required this.value});

  /// The selector that names it: `Login`, or `Auth/Login`.
  String get path => folderPath.isEmpty ? name : '$folderPath/$name';
}

sealed class ReloginLookup<T> {
  const ReloginLookup();
}

final class ReloginFound<T> extends ReloginLookup<T> {
  final ReloginCandidate<T> candidate;
  const ReloginFound(this.candidate);
}

final class ReloginNotFound<T> extends ReloginLookup<T> {
  const ReloginNotFound();
}

final class ReloginAmbiguous<T> extends ReloginLookup<T> {
  final int count;
  const ReloginAmbiguous(this.count);
}

/// The rules of "on 401/403 run the login request, then retry once", apart from how a request is run.
abstract final class ReloginPolicy {
  /// The config in force for a request below [chain]: the nearest folder that sets one, else the
  /// collection's. A folder's config replaces the collection's for the requests below it.
  static ReloginConfig? configIn(DefaultsChain chain) {
    for (final scope in chain.scopes.reversed) {
      final config = scope.defaults.auth?.relogin;
      if (config != null && config.isActive) return config;
    }
    return null;
  }

  /// The request [selector] names among [candidates]: a full `Folder/Name` path first, then a bare name.
  /// Two requests with the same path (or the same bare name) are ambiguous rather than guessed at.
  static ReloginLookup<T> find<T>(String selector, Iterable<ReloginCandidate<T>> candidates) {
    final wanted = selector.trim();
    final byPath = [for (final c in candidates) if (c.path == wanted) c];
    if (byPath.length == 1) return ReloginFound(byPath.single);
    if (byPath.length > 1) return ReloginAmbiguous(byPath.length);
    final byName = [for (final c in candidates) if (c.name == wanted) c];
    if (byName.length == 1) return ReloginFound(byName.single);
    if (byName.length > 1) return ReloginAmbiguous(byName.length);
    return const ReloginNotFound();
  }

  /// A login is a call that signs in, so it is a GET or a POST. Anything else (a DELETE or PUT picked
  /// by mistake, or arriving through a shared workspace) would run unasked on every 401, so it is refused.
  static String? methodProblem(HttpMethod method) => method == HttpMethod.get || method == HttpMethod.post
      ? null
      : 'it is a ${method.label} request; a login request must be a GET or a POST';

  /// Said on the response when the login ran and the request was sent again.
  static String retriedNote(String request, int firstStatus) =>
      'Re-authenticated via "$request" and retried (the first answer was HTTP $firstStatus).';

  static String failedNote(String request, String why) =>
      'Re-login via "$request" failed ($why), so the request was not retried.';

  static String skippedNote(String request, String why) => 'Re-login via "$request" skipped: $why.';

  static String notFoundNote(String request) =>
      'Re-login is set to "$request", but no request of this collection has that name, so nothing was retried. '
      'Pick the login request again in the Auth tab.';

  static String ambiguousNote(String request, int count) =>
      'Re-login is set to "$request", which names $count requests, so nothing was retried. '
      'Rename one of them, or pick the login request again in the Auth tab.';

  static String methodNote(String request, String problem) =>
      'Re-login via "$request" was not run: $problem.';

  /// Whether a note from this class (or from the token renewal) reports something that did not work, so
  /// the response can show it as a warning rather than as plain information.
  static bool isProblem(String note) =>
      note.startsWith('Could not renew') ||
      note.startsWith('Re-login is set to') ||
      (note.startsWith('Re-login via') && (note.contains(' failed (') || note.contains(' skipped: ') || note.contains(' was not run: ')));
}
