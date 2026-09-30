/// A fully-resolved, ready-to-send request: every `{{variable}}` substituted,
/// every auth header computed. Shared by [SendRequestUseCase] (which sends
/// it) and the code generators (which print it in another language) so both
/// stay byte-for-byte consistent with what's actually transmitted.
final class ResolvedRequestSpec {
  final String method;
  final String url;
  final Map<String, String> headers;
  final List<int>? bodyBytes;

  const ResolvedRequestSpec({
    required this.method,
    required this.url,
    required this.headers,
    required this.bodyBytes,
  });
}
