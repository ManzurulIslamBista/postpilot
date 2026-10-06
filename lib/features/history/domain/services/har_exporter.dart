import 'dart:convert';
import '../../../documentation/domain/services/secret_masker.dart';
import '../../../git_sync/domain/services/secret_names.dart';

final class HarHeader {
  final String name;
  final String value;
  const HarHeader(this.name, this.value);
}

/// One recorded send, in the terms HAR uses. Built from History entries by
/// `HistoryHar`; every text here is masked again by [HarExporter], so an input
/// built from anywhere cannot put a credential into the file.
final class HarEntryInput {
  final DateTime startedAt;

  /// The whole send, in milliseconds; null when it was not recorded.
  final int? durationMs;
  final String method;

  /// Absolute where it can be; History keeps `{{variables}}` as written.
  final String url;
  final List<HarHeader> requestHeaders;
  final String? requestMimeType;

  /// The request body as text (not for a multipart form, which has [requestParams]).
  final String? requestBody;

  /// The fields of a multipart form.
  final List<HarHeader>? requestParams;

  /// Null for a send that got no response (DNS, refused, timeout): HAR writes status 0.
  final int? statusCode;
  final String statusText;
  final List<HarHeader> responseHeaders;
  final String? responseMimeType;

  /// The response body when it is text; null when it was binary, empty or not kept.
  final String? responseText;

  /// The size of the response body as received; null when unknown (HAR writes -1).
  final int? responseBytes;
  final bool responseTruncated;

  /// Why there was no response.
  final String? error;
  final String? comment;

  const HarEntryInput({
    required this.startedAt,
    required this.method,
    required this.url,
    this.durationMs,
    this.requestHeaders = const [],
    this.requestMimeType,
    this.requestBody,
    this.requestParams,
    this.statusCode,
    this.statusText = '',
    this.responseHeaders = const [],
    this.responseMimeType,
    this.responseText,
    this.responseBytes,
    this.responseTruncated = false,
    this.error,
    this.comment,
  });
}

/// Writes History as a HAR 1.2 file (http://www.softwareishard.com/blog/har-12-spec/),
/// the format browsers' dev tools, Charles, Fiddler and PostPilot's own importer read.
///
/// Only what is known is written. HAR asks for numbers everywhere, and `-1`
/// means "not available" in its own words: PostPilot knows the total time of a
/// send but not its DNS, connect or TLS parts, and not the size of the headers
/// or of the body on the wire, so those are `-1`. The `send`, `wait` and `receive`
/// timings are required and may not be negative, so the whole time is `wait` and
/// the other two are 0; `time` is their sum, as the spec says it is.
///
/// Response headers are not in History (they hold cookies and tokens), so a
/// response carries only its `Content-Type`. Credentials in the URL, the request
/// headers and the bodies are masked, whatever the input holds.
abstract final class HarExporter {
  static const harVersion = '1.2';
  static const creatorName = 'PostPilot';

  static String export(List<HarEntryInput> entries, {String creatorVersion = '1.0'}) =>
      const JsonEncoder.withIndent('  ').convert(build(entries, creatorVersion: creatorVersion));

  static Map<String, Object?> build(List<HarEntryInput> entries, {String creatorVersion = '1.0'}) => {
        'log': {
          'version': harVersion,
          'creator': {'name': creatorName, 'version': creatorVersion},
          'entries': [for (final entry in entries) _entry(entry)],
        },
      };

  static Map<String, Object?> _entry(HarEntryInput e) {
    final duration = e.durationMs != null && e.durationMs! >= 0 ? e.durationMs! : 0;
    final url = SecretMasker.maskUrl(e.url);
    return {
      'startedDateTime': e.startedAt.toUtc().toIso8601String(),
      'time': duration,
      'request': _request(e, url),
      'response': _response(e),
      'cache': <String, Object?>{},
      'timings': {
        'blocked': -1,
        'dns': -1,
        'connect': -1,
        'ssl': -1,
        'send': 0,
        'wait': duration,
        'receive': 0,
      },
      if (e.comment != null && e.comment!.isNotEmpty) 'comment': e.comment,
    };
  }

  static Map<String, Object?> _request(HarEntryInput e, String url) {
    final body = e.requestBody == null ? null : SecretMasker.maskBody(e.requestBody!);
    final params = e.requestParams;
    final mime = e.requestMimeType ?? '';
    return {
      'method': e.method,
      'url': url,
      'httpVersion': 'HTTP/1.1',
      'cookies': const <Object?>[],
      'headers': _headers(e.requestHeaders, mask: true),
      'queryString': _queryString(url),
      if (params != null && params.isNotEmpty)
        'postData': {
          'mimeType': mime.isEmpty ? 'multipart/form-data' : mime,
          'params': [
            for (final p in params) {'name': p.name, 'value': SecretMasker.maskValue(p.name, p.value)},
          ],
        }
      else if (body != null && body.isNotEmpty)
        'postData': {'mimeType': mime, 'text': body},
      'headersSize': -1,
      'bodySize': body == null ? 0 : utf8.encode(body).length,
    };
  }

  static Map<String, Object?> _response(HarEntryInput e) {
    final status = e.statusCode;
    final text = e.responseText == null ? null : SecretMasker.maskBody(e.responseText!);
    final error = e.error == null ? null : SecretMasker.maskMessage(e.error!);
    final notes = [
      if (e.responseTruncated) 'The response body was cut off: History keeps only the first part of it.',
      ?error,
    ];
    return {
      'status': status ?? 0,
      'statusText': e.statusText,
      'httpVersion': 'HTTP/1.1',
      'cookies': const <Object?>[],
      'headers': _headers(e.responseHeaders, mask: true),
      'content': {
        'size': e.responseBytes ?? (text == null ? -1 : utf8.encode(text).length),
        'mimeType': e.responseMimeType ?? '',
        if (text != null && text.isNotEmpty) 'text': text,
        if (notes.isNotEmpty) 'comment': notes.join(' '),
      },
      'redirectURL': '',
      'headersSize': -1,
      'bodySize': -1,
      '_error': ?error,
    };
  }

  static List<Map<String, String>> _headers(List<HarHeader> headers, {required bool mask}) => [
        for (final h in headers)
          {
            'name': h.name,
            'value': mask
                ? SecretMasker.maskValue(SecretNames.isSecretHeader(h.name) && !SecretMasker.isSensitiveName(h.name) ? 'authorization' : h.name, h.value)
                : h.value,
          },
      ];

  /// The query of [url] as HAR lists it; a pair without `=` has an empty value.
  static List<Map<String, String>> _queryString(String url) {
    final question = url.indexOf('?');
    if (question == -1) return const [];
    final hash = url.indexOf('#', question);
    final query = url.substring(question + 1, hash == -1 ? url.length : hash);
    return [
      for (final pair in query.split('&'))
        if (pair.isNotEmpty)
          {
            'name': _decode(pair.contains('=') ? pair.substring(0, pair.indexOf('=')) : pair),
            'value': _decode(pair.contains('=') ? pair.substring(pair.indexOf('=') + 1) : ''),
          },
    ];
  }

  static String _decode(String text) {
    try {
      return Uri.decodeQueryComponent(text);
    } catch (_) {
      return text;
    }
  }
}
