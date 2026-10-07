// Pure Dart on purpose (no Flutter, no dart:io): the recorder engine can then be started from a plain `dart run` script.
import 'dart:convert';
import 'dart:typed_data';

/// One header exactly as it was on the wire; a name can repeat (`Set-Cookie`).
final class RecordedHeader {
  final String name;
  final String value;
  const RecordedHeader(this.name, this.value);

  @override
  String toString() => '$name: $value';
}

/// What became of a request that reached the recorder.
enum RecordedKind {
  /// Forwarded to the upstream and answered with what the upstream said.
  proxied,

  /// The upstream could not be reached or broke off; the app got a 502 from the recorder.
  upstreamFailed,

  /// A request the recorder does not forward (WebSocket upgrade, CONNECT); the app got a 501 from the recorder.
  refused,
}

/// One call the app made through the recorder, with the answer it got.
///
/// Holds the real values (tokens included) because the live view can show them on request; anything that is saved,
/// copied or exported goes through `TrafficMasking` first. Bodies are the decoded copy the recorder kept (a gzip body is
/// stored inflated), cut at the recorder's size cap, with the flags that say so.
final class RecordedExchange {
  final int id;
  final DateTime startedAt;
  final Duration duration;
  final String method;

  /// The address that was requested upstream, query included. For a call that was refused, the address as received.
  final String url;

  /// Path and query as the app sent them (without the upstream's own path prefix); what the app-facing table shows.
  final String path;
  final String? clientAddress;
  final RecordedKind kind;

  final List<RecordedHeader> requestHeaders;
  final Uint8List requestBody;

  /// Bytes the app sent (before any decoding); more than [requestBody] holds when it was cut.
  final int requestBodySize;
  final bool requestBodyTruncated;

  /// The status the app saw (502 / 501 for a call the recorder answered itself).
  final int status;
  final String statusMessage;
  final List<RecordedHeader> responseHeaders;
  final Uint8List responseBody;

  /// Bytes on the wire, i.e. as sent by the upstream (compressed when it was compressed).
  final int responseBodySize;
  final bool responseBodyTruncated;

  /// The `Content-Encoding` of the answer when there was one (`gzip`).
  final String? responseEncoding;

  /// The answer is compressed in a way the recorder cannot undo (brotli): [responseBody] is the raw bytes.
  final bool responseUndecoded;

  /// Why the call failed or was refused (never holds a credential); null for a forwarded call.
  final String? error;

  RecordedExchange({
    required this.id,
    required this.startedAt,
    required this.duration,
    required this.method,
    required this.url,
    required this.path,
    required this.status,
    this.statusMessage = '',
    this.clientAddress,
    this.kind = RecordedKind.proxied,
    this.requestHeaders = const [],
    Uint8List? requestBody,
    this.requestBodySize = 0,
    this.requestBodyTruncated = false,
    this.responseHeaders = const [],
    Uint8List? responseBody,
    this.responseBodySize = 0,
    this.responseBodyTruncated = false,
    this.responseEncoding,
    this.responseUndecoded = false,
    this.error,
  })  : requestBody = requestBody ?? Uint8List(0),
        responseBody = responseBody ?? Uint8List(0);

  /// First value of the header [name] (case-insensitive) among [headers], null when absent.
  static String? headerOf(List<RecordedHeader> headers, String name) {
    final lower = name.toLowerCase();
    for (final h in headers) {
      if (h.name.toLowerCase() == lower) return h.value;
    }
    return null;
  }

  String? requestHeader(String name) => headerOf(requestHeaders, name);
  String? responseHeader(String name) => headerOf(responseHeaders, name);

  String? get requestContentType => requestHeader('content-type');
  String? get responseContentType => responseHeader('content-type');

  /// The upstream host of [url] (empty when it cannot be read).
  String get host => Uri.tryParse(url)?.host ?? '';

  bool get succeeded => status >= 200 && status < 400;

  /// The request body as text; null when it is empty or not text (an upload, an image).
  late final String? requestText = _textOf(requestBody, requestContentType, requestBodyTruncated);

  /// The response body as text; null when it is empty, not text, or compressed in a way that cannot be read.
  late final String? responseText = responseUndecoded ? null : _textOf(responseBody, responseContentType, responseBodyTruncated);

  bool get hasRequestBody => requestBodySize > 0;
  bool get hasResponseBody => responseBodySize > 0;

  /// Roughly what keeping this exchange costs, for the recorder's memory budget.
  int get approximateBytes => 1024 + requestBody.length + responseBody.length;

  static final _textTypes = RegExp(
    r'^(text/|application/(json|xml|javascript|x-www-form-urlencoded|graphql|yaml|x-yaml|x-ndjson|ld\+json)|.*[+/](json|xml|yaml)$)',
  );

  static String? _textOf(Uint8List bytes, String? contentType, bool truncated) {
    if (bytes.isEmpty) return null;
    final mime = (contentType ?? '').split(';').first.trim().toLowerCase();
    final charset = RegExp(r'charset\s*=\s*"?([\w-]+)', caseSensitive: false).firstMatch(contentType ?? '')?.group(1)?.toLowerCase();
    if (mime.isNotEmpty && _textTypes.hasMatch(mime)) {
      if (charset == 'iso-8859-1' || charset == 'latin1' || charset == 'us-ascii') return latin1.decode(bytes);
      return utf8.decode(bytes, allowMalformed: true);
    }
    if (mime.isNotEmpty && !mime.startsWith('application/octet') && mime != 'binary/octet-stream') {
      // A declared binary type (image/png, application/pdf, multipart/form-data, protobuf...).
      return null;
    }
    // No usable type: text when it decodes cleanly as UTF-8 and holds no control bytes.
    try {
      final text = utf8.decode(truncated ? _withoutPartialTail(bytes) : bytes);
      return text.codeUnits.any((c) => c == 0) ? null : text;
    } on FormatException {
      return null;
    }
  }

  /// A body cut in the middle of a multi-byte character ends in a lead byte the strict decoder rejects: drop up to three.
  static Uint8List _withoutPartialTail(Uint8List bytes) {
    var end = bytes.length;
    var dropped = 0;
    while (end > 0 && dropped < 3 && (bytes[end - 1] & 0xC0) == 0x80) {
      end--;
      dropped++;
    }
    if (end > 0 && bytes[end - 1] >= 0xC0) end--;
    return Uint8List.sublistView(bytes, 0, end);
  }
}
