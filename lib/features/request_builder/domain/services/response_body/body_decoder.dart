import 'dart:convert';
import 'dart:typed_data';

enum _Encoding { utf8, utf16le, utf16be, windows1252 }

final _charsetParam = RegExp(r'charset\s*=\s*"?([^\s";]+)', caseSensitive: false);
final _xmlDeclaration = RegExp(r'''^\s*<\?xml[^>]*?\sencoding\s*=\s*["']([^"']+)["']''', caseSensitive: false);
final _htmlMeta = RegExp(r'''<meta[^>]+charset\s*=\s*["']?([\w-]+)''', caseSensitive: false);
final _textualMimeType = RegExp(r'^text/|json|xml|javascript|ecmascript|yaml|urlencoded|graphql|csv');

// The C1 range (0x80-0x9F) of windows-1252; every other byte maps to the code
// point of the same value, as in Latin-1.
const _windows1252C1 = <int>[
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
];

/// The `charset` parameter of a Content-Type header value, or null.
String? charsetOfContentType(String? contentType) =>
    contentType == null ? null : _charsetParam.firstMatch(contentType)?[1];

/// Decodes a response body the way a browser would: a byte-order mark wins,
/// then the charset the server declared, then the encoding an XML/HTML
/// document declares about itself, then UTF-8. Returns null for binary
/// content.
///
/// Only UTF-8, UTF-16 and windows-1252 (which browsers also use for
/// ISO-8859-1 and US-ASCII) are understood; a body in any other charset is
/// decoded as if none was declared.
///
/// With [truncated] the body was cut off at the response size limit, possibly
/// in the middle of a multi-byte UTF-8 character; that incomplete tail is
/// dropped instead of making the whole body look like invalid UTF-8.
String? decodeResponseBody(Uint8List bytes, {required String mimeType, String? charset, bool truncated = false}) {
  if (bytes.isEmpty) return '';
  final isTextual = _textualMimeType.hasMatch(mimeType);
  final bom = isTextual || mimeType.isEmpty ? _byteOrderMark(bytes) : null;
  final encoding = bom?.encoding ?? _encodingOf(charset) ?? _declaredEncoding(bytes, mimeType);
  final body = bom == null ? bytes : Uint8List.sublistView(bytes, bom.length);

  switch (encoding) {
    case _Encoding.utf16le:
      return _decodeUtf16(body, bigEndian: false);
    case _Encoding.utf16be:
      return _decodeUtf16(body, bigEndian: true);
    case _Encoding.windows1252:
      return _hasNul(body) ? null : _decodeWindows1252(body);
    case _Encoding.utf8:
    case null:
      if (_hasNul(body)) return null;
      final complete = truncated ? _withoutIncompleteUtf8Tail(body) : body;
      try {
        return utf8.decode(complete);
      } on FormatException {
        if (encoding == _Encoding.utf8) return utf8.decode(complete, allowMalformed: true);
        if (mimeType.startsWith('text/')) return _decodeWindows1252(body);
        return isTextual ? utf8.decode(complete, allowMalformed: true) : null;
      }
  }
}

/// [bytes] without a final UTF-8 sequence whose continuation bytes were cut
/// off. A tail that is complete, or not UTF-8 at all, is left alone.
Uint8List _withoutIncompleteUtf8Tail(Uint8List bytes) {
  var start = bytes.length - 1;
  var continuationBytes = 0;
  while (start >= 0 && continuationBytes < 3 && (bytes[start] & 0xC0) == 0x80) {
    start--;
    continuationBytes++;
  }
  if (start < 0) return bytes;
  final lead = bytes[start];
  final needed = lead >= 0xF0
      ? 3
      : lead >= 0xE0
          ? 2
          : lead >= 0xC0
              ? 1
              : 0;
  return needed > continuationBytes ? Uint8List.sublistView(bytes, 0, start) : bytes;
}

({_Encoding encoding, int length})? _byteOrderMark(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return (encoding: _Encoding.utf8, length: 3);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) return (encoding: _Encoding.utf16le, length: 2);
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) return (encoding: _Encoding.utf16be, length: 2);
  return null;
}

_Encoding? _encodingOf(String? label) => switch (label?.trim().toLowerCase()) {
      'utf-8' || 'utf8' => _Encoding.utf8,
      'utf-16le' || 'utf-16' || 'ucs-2' => _Encoding.utf16le,
      'utf-16be' => _Encoding.utf16be,
      'windows-1252' ||
      'cp1252' ||
      'x-cp1252' ||
      'iso-8859-1' ||
      'iso8859-1' ||
      'iso_8859-1' ||
      'latin1' ||
      'l1' ||
      'us-ascii' ||
      'ascii' =>
        _Encoding.windows1252,
      _ => null,
    };

_Encoding? _declaredEncoding(Uint8List bytes, String mimeType) {
  final isXml = mimeType.contains('xml');
  if (!isXml && mimeType != 'text/html') return null;
  final head = latin1.decode(Uint8List.sublistView(bytes, 0, bytes.length < 1024 ? bytes.length : 1024));
  return _encodingOf((isXml ? _xmlDeclaration : _htmlMeta).firstMatch(head)?[1]);
}

// A NUL byte in the first few KB is how git and most editors tell binary
// content from text.
bool _hasNul(Uint8List bytes) {
  final end = bytes.length < 8192 ? bytes.length : 8192;
  for (var i = 0; i < end; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

String _decodeWindows1252(Uint8List bytes) {
  final units = Uint16List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    units[i] = byte >= 0x80 && byte <= 0x9F ? _windows1252C1[byte - 0x80] : byte;
  }
  return String.fromCharCodes(units);
}

// Dart strings may hold unpaired surrogates but Flutter's text engine rejects
// them, so any that the input contains become U+FFFD.
String _decodeUtf16(Uint8List bytes, {required bool bigEndian}) {
  final units = Uint16List(bytes.length ~/ 2);
  for (var i = 0; i < units.length; i++) {
    final first = bytes[2 * i];
    final second = bytes[2 * i + 1];
    units[i] = bigEndian ? (first << 8) | second : (second << 8) | first;
  }
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    final isHigh = unit >= 0xD800 && unit <= 0xDBFF;
    if (isHigh && i + 1 < units.length && units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF) {
      i++;
    } else if (isHigh || (unit >= 0xDC00 && unit <= 0xDFFF)) {
      units[i] = 0xFFFD;
    }
  }
  return String.fromCharCodes(units);
}
