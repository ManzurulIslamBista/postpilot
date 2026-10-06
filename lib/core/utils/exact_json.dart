import 'dart:convert';

/// Decodes JSON the way [jsonDecode] does, except that an integer a `num`
/// cannot hold exactly comes back as a [BigInt] instead of a rounded double.
///
/// On the web every JSON number is a double, so an id such as
/// `1234567890123456789` (a Twitter-style snowflake, a 64-bit database key) is
/// read as `1234567890123456800` and an extractor would save the wrong value.
/// The VM keeps 64-bit integers exactly and only rounds past that.
abstract final class ExactJson {
  /// Largest integer a JavaScript number holds exactly: 2^53.
  static final _webLimit = BigInt.one << 53;
  static final _vmMax = (BigInt.one << 63) - BigInt.one;
  static final _vmMin = -(BigInt.one << 63);

  static final _longDigits = RegExp(r'\d{16}');

  /// A NUL cannot appear raw in a JSON string, so the text only holds one as
  /// the escape `\u0000`: when it does not, no string of the document can start
  /// with the [_marker] that stands in for a large integer while it is decoded.
  static final _nulEscape = RegExp(r'\\u0000', caseSensitive: false);
  static const _marker = '\u0000bigint:';

  /// How [_marker] is written into the JSON text: a raw control character is
  /// not valid inside a JSON string, its escape is.
  static const _escapedMarker = r'\u0000bigint:';

  /// Whether this runs on the web, where the number type is the JavaScript one.
  static const isWeb = identical(0, 0.0);

  /// The document of [text] with its large integers exact, or null when it
  /// holds none (or is not JSON), in which case [jsonDecode] already gives the
  /// right values. [web] only exists for tests.
  static Object? decodeIfLarge(String text, {bool web = isWeb}) {
    if (!_longDigits.hasMatch(text) || _nulEscape.hasMatch(text)) return null;
    final rewritten = _quoteLargeIntegers(text, web: web);
    if (rewritten == null) return null;
    try {
      return jsonDecode(
        rewritten,
        reviver: (key, value) =>
            value is String && value.startsWith(_marker) ? BigInt.parse(value.substring(_marker.length)) : value,
      );
    } on FormatException {
      return null;
    }
  }

  /// [text] with every integer literal outside the exact range written as a
  /// marked string; null when there is none. Walks the text once, skipping
  /// strings, so a number-like run inside a string is left alone.
  static String? _quoteLargeIntegers(String text, {required bool web}) {
    StringBuffer? out;
    var copiedTo = 0;
    var i = 0;
    final n = text.length;
    while (i < n) {
      final c = text.codeUnitAt(i);
      if (c == 0x22) {
        i = _endOfString(text, i);
      } else if (c == 0x2d || _isDigit(c)) {
        final start = i;
        if (c == 0x2d) i++;
        final digitsStart = i;
        while (i < n && _isDigit(text.codeUnitAt(i))) {
          i++;
        }
        final digits = i - digitsStart;
        final fractionOrExponent = i < n && (text[i] == '.' || text[i] == 'e' || text[i] == 'E');
        if (fractionOrExponent) {
          // A float literal: leave it to the decoder, skipping what it consists of.
          while (i < n && '0123456789.eE+-'.contains(text[i])) {
            i++;
          }
        } else if (digits >= 16 && !_isExact(BigInt.parse(text.substring(start, i)), web: web)) {
          (out ??= StringBuffer())
            ..write(text.substring(copiedTo, start))
            ..write('"$_escapedMarker${text.substring(start, i)}"');
          copiedTo = i;
        }
      } else {
        i++;
      }
    }
    if (out == null) return null;
    return (out..write(text.substring(copiedTo))).toString();
  }

  static bool _isExact(BigInt value, {required bool web}) =>
      web ? value.abs() <= _webLimit : value >= _vmMin && value <= _vmMax;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  /// The index just past the string that starts at [start] (a `"`).
  static int _endOfString(String text, int start) {
    var i = start + 1;
    while (i < text.length) {
      final c = text.codeUnitAt(i);
      if (c == 0x5c) {
        i += 2;
      } else if (c == 0x22) {
        return i + 1;
      } else {
        i++;
      }
    }
    return text.length;
  }
}
