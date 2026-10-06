import '../../../documentation/domain/services/secret_masker.dart';
import '../../../request_builder/domain/services/code_generators/string_literals.dart';

/// What the request log may keep of a request. Credentials never reach the log: the headers, the address and the
/// body are masked with the app's own [SecretMasker] before anything is stored, so a copied cURL command or a
/// screenshot of the log cannot leak them.
abstract final class MockLogMasking {
  /// How much of a body the log keeps.
  static const bodyLimit = 4000;

  /// Headers the caller's HTTP client adds on its own and a cURL command does not need.
  static const _skipHeaders = {
    'host', 'content-length', 'connection', 'accept-encoding', 'user-agent', 'keep-alive', 'transfer-encoding', 'upgrade',
  };

  /// [headers] with every credential value masked (`Authorization: Bearer ••••••`), without the transport headers.
  static Map<String, String> headers(Map<String, String> headers) => {
        for (final e in headers.entries)
          if (!_skipHeaders.contains(e.key.toLowerCase())) e.key: SecretMasker.maskValue(e.key, e.value),
      };

  /// `path?query` with a password in the address and the value of a secret query parameter masked.
  static String target(String target) => SecretMasker.maskUrl(target);

  /// [body] with credentials masked, cut to [bodyLimit] characters.
  static String body(String body) {
    final masked = SecretMasker.maskBody(body);
    return masked.length <= bodyLimit ? masked : '${masked.substring(0, bodyLimit)}…';
  }

  /// A short, single-line preview of an already masked body, for a list row.
  static String preview(String maskedBody, {int length = 80}) {
    final oneLine = maskedBody.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length <= length ? oneLine : '${oneLine.substring(0, length)}…';
  }
}

/// A cURL command that repeats a logged request.
abstract final class MockCurl {
  /// [url] is the whole address (`http://localhost:3001/users?page=2`). The headers and the body are what the log kept,
  /// so they are masked already.
  static String build({required String method, required String url, Map<String, String> headers = const {}, String body = ''}) {
    final lines = ['curl --request ${shellWord(method)} ${shellQuote(url)}'];
    for (final e in headers.entries) {
      lines.add('--header ${shellQuote(e.value.isEmpty ? '${e.key};' : '${e.key}: ${e.value}')}');
    }
    if (body.isNotEmpty) lines.add('--data-raw ${shellQuote(body)}');
    return shellLines(lines, indent: '  ');
  }
}
