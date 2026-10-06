import '../../../../core/network/upload_body.dart';

/// A fully-resolved, ready-to-send request: every `{{variable}}` substituted,
/// every auth header computed. Shared by [SendRequestUseCase] (which sends
/// it) and the code generators (which print it in another language) so both
/// stay byte-for-byte consistent with what's actually transmitted.
final class ResolvedRequestSpec {
  final String method;
  final String url;
  final Map<String, String> headers;
  final List<int>? bodyBytes;

  /// Set instead of [bodyBytes] when the body carries a file (a form-data `file` part, a binary body): the
  /// reference to it, read in chunks when the request is sent. Never holds file content.
  final UploadBody? upload;

  const ResolvedRequestSpec({
    required this.method,
    required this.url,
    required this.headers,
    required this.bodyBytes,
    this.upload,
  });

  /// What goes to the HTTP client as the body: the [upload] when there is one, else the bytes.
  Object? get wireBody => upload ?? bodyBytes;
}
