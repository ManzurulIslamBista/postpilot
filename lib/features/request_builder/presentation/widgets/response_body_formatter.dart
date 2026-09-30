import 'dart:convert';
import 'dart:typed_data';
import '../../../../core/utils/safe_file_name.dart';
import '../../domain/services/response_body/body_decoder.dart';
import '../../domain/services/response_body/download_file_name.dart';
import '../../domain/services/response_body/html_preview.dart';
import '../../domain/services/response_body/pretty_printer.dart';

enum ResponseContentKind { json, html, xml, image, text, binary }

enum ResponseBodyMode { pretty, raw, preview }

/// The most text laid out at once. Flutter lays a text paragraph out in full,
/// so a multi-megabyte body would freeze the UI; Copy and Download still
/// carry the whole body.
const maxDisplayedBodyChars = 512 * 1024;

/// The most search matches highlighted (and counted) at once.
const maxSearchHighlights = 1000;

// Larger bodies are shown as received instead of being re-indented on the UI
// thread.
const _maxPrettyPrintChars = 5 * 1024 * 1024;

/// Display-side view of a response body: what kind of content it is, its
/// decoded text, and the Pretty/Raw/Preview renderings, each computed once.
final class ResponseBodyFormatter {
  final Uint8List bytes;
  final String mimeType;
  final String? text;
  final ResponseContentKind kind;
  final String? _contentDisposition;

  ResponseBodyFormatter._({
    required this.bytes,
    required this.mimeType,
    required this.text,
    required this.kind,
    required this._contentDisposition,
  });

  factory ResponseBodyFormatter(Map<String, String> headers, Uint8List bytes) {
    final contentType = _headerValue(headers, 'content-type');
    final mimeType = _mimeTypeOf(contentType);
    final text = decodeResponseBody(bytes, mimeType: mimeType, charset: charsetOfContentType(contentType));
    return ResponseBodyFormatter._(
      bytes: bytes,
      mimeType: mimeType,
      text: text,
      kind: _detectKind(mimeType, text),
      contentDisposition: _headerValue(headers, 'content-disposition'),
    );
  }

  /// For a body that is already text (a saved example), so the charset named
  /// in [headers] must not be applied to it a second time.
  factory ResponseBodyFormatter.fromText(Map<String, String> headers, String text) {
    final mimeType = _mimeTypeOf(_headerValue(headers, 'content-type'));
    return ResponseBodyFormatter._(
      bytes: utf8.encode(text),
      mimeType: mimeType,
      text: text,
      kind: _detectKind(mimeType, text),
      contentDisposition: _headerValue(headers, 'content-disposition'),
    );
  }

  /// Whether the body can be shown as, copied as and saved as text.
  bool get isTextual => text != null && kind != ResponseContentKind.image;

  late final String raw = text ?? '<${bytes.length} bytes of binary data>';
  late final String pretty = _prettyPrint();
  late final String preview = _previewOf();
  final _displayTexts = <ResponseBodyMode, String>{};

  String textFor(ResponseBodyMode mode) => switch (mode) {
        ResponseBodyMode.pretty => pretty,
        ResponseBodyMode.raw => raw,
        ResponseBodyMode.preview => preview,
      };

  /// [textFor] cut to [maxDisplayedBodyChars]; the same instance every call.
  String displayTextFor(ResponseBodyMode mode) => _displayTexts.putIfAbsent(mode, () => _truncated(textFor(mode)));

  bool isTruncated(ResponseBodyMode mode) => textFor(mode).length > maxDisplayedBodyChars;

  String get downloadMimeType => mimeType.isEmpty ? 'application/octet-stream' : mimeType;

  String get fileExtension =>
      extensionForMimeType(mimeType) ??
      switch (kind) {
        ResponseContentKind.json => 'json',
        ResponseContentKind.html => 'html',
        ResponseContentKind.xml => 'xml',
        ResponseContentKind.text => 'txt',
        ResponseContentKind.image || ResponseContentKind.binary => 'bin',
      };

  /// The name to save the body under: the server's suggestion (reduced to a
  /// safe file name) when there is one, otherwise [requestName].
  String downloadFileName({String? requestName}) {
    final suggested = fileNameFromContentDisposition(_contentDisposition, fallbackExtension: fileExtension);
    return suggested ?? '${sanitizeFileName(requestName ?? '') ?? 'response'}.$fileExtension';
  }

  String _prettyPrint() {
    final decoded = text;
    if (decoded == null) return raw;
    if (decoded.length > _maxPrettyPrintChars) return decoded;
    final isMarkup = decoded.trimLeft().startsWith('<');
    try {
      // Anything else that parses as a JSON object or array is indented too,
      // whatever the server labelled it; anything that does not stays as is.
      return switch (kind) {
        ResponseContentKind.xml when isMarkup => prettyPrintMarkup(decoded, html: false),
        ResponseContentKind.html when isMarkup => prettyPrintMarkup(decoded, html: true),
        _ => prettyPrintJson(decoded),
      };
    } catch (_) {
      return decoded;
    }
  }

  String _previewOf() {
    final decoded = text;
    if (decoded == null || kind != ResponseContentKind.html) return pretty;
    try {
      return htmlToPlainText(decoded);
    } catch (_) {
      return decoded;
    }
  }

  static String? _headerValue(Map<String, String> headers, String lowerCaseName) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lowerCaseName) return entry.value;
    }
    return null;
  }

  static String _mimeTypeOf(String? contentType) =>
      contentType == null ? '' : contentType.split(';').first.trim().toLowerCase();

  static ResponseContentKind _detectKind(String mimeType, String? decoded) {
    if (mimeType.startsWith('image/') && mimeType != 'image/svg+xml') return ResponseContentKind.image;
    if (mimeType.contains('json')) return ResponseContentKind.json;
    if (mimeType == 'text/html' || mimeType == 'application/xhtml+xml') return ResponseContentKind.html;
    if (mimeType.contains('xml')) return ResponseContentKind.xml;
    if (decoded == null) return ResponseContentKind.binary;
    final head = decoded.trimLeft();
    final tail = decoded.trimRight();
    if ((head.startsWith('{') && tail.endsWith('}')) || (head.startsWith('[') && tail.endsWith(']'))) {
      return ResponseContentKind.json;
    }
    if (RegExp(r'^<(!doctype\s+html|html)', caseSensitive: false).hasMatch(head)) return ResponseContentKind.html;
    if (head.startsWith('<?xml')) return ResponseContentKind.xml;
    return ResponseContentKind.text;
  }

  static String _truncated(String text) {
    if (text.length <= maxDisplayedBodyChars) return text;
    var end = maxDisplayedBodyChars;
    final lastNewline = text.lastIndexOf('\n', end - 1);
    if (lastNewline > end ~/ 2) {
      end = lastNewline;
    } else {
      // Flutter's text engine throws on a lone surrogate, so never cut a pair in half.
      final last = text.codeUnitAt(end - 1);
      if (last >= 0xD800 && last <= 0xDBFF) end--;
    }
    return text.substring(0, end);
  }
}

/// Start offsets of every non-overlapping, case-insensitive occurrence of
/// [query] in [text], at most [limit] of them.
List<int> findMatches(String text, String query, {int limit = maxSearchHighlights}) {
  if (query.isEmpty) return const [];
  var haystack = text.toLowerCase();
  var needle = query.toLowerCase();
  if (haystack.length != text.length || needle.length != query.length) {
    haystack = text;
    needle = query;
  }
  final matches = <int>[];
  var index = haystack.indexOf(needle);
  while (index != -1 && matches.length < limit) {
    matches.add(index);
    index = haystack.indexOf(needle, index + needle.length);
  }
  return matches;
}
