import 'dart:convert';

/// A JSON text that may hold bare `{{variables}}` where a number goes (`"partner_id": {{partnerId}}`,
/// `[{{recordId}}]`, `{{xmlid:base.main_company}}`). Such a text is JSON only once its variables are filled in, but
/// it is how requests are saved, so the tools of Studio read and write it as it is: each bare token is read as a
/// placeholder value ([isToken]) that no type check applies to, and written back exactly as it was.
final class OdooJsonDoc {
  static const _prefix = '__postpilot_token_';
  static const _suffix = '__';

  /// The decoded document; a bare token is a placeholder string (see [isToken]).
  final Object? value;

  /// The token each placeholder of [value] stands for.
  final Map<String, String> tokens;

  const OdooJsonDoc(this.value, [this.tokens = const {}]);

  static bool isToken(Object? v) => v is String && v.startsWith(_prefix) && v.endsWith(_suffix);

  /// The placeholder string with this [index] (what a value holds in place of a bare token).
  static String placeholder(int index) => '$_prefix$index$_suffix';

  /// Reads [text]; [error] says what is wrong when it is not JSON.
  static ({OdooJsonDoc? doc, String? error}) parse(String text) {
    final tokens = <String, String>{};
    final out = StringBuffer();
    var inString = false;
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (inString) {
        out.write(c);
        if (c == r'\' && i + 1 < text.length) {
          out.write(text[i + 1]);
          i += 2;
          continue;
        }
        if (c == '"') inString = false;
        i++;
        continue;
      }
      if (c == '"') {
        inString = true;
        out.write(c);
        i++;
        continue;
      }
      if (c == '{' && text.startsWith('{{', i)) {
        final end = text.indexOf('}}', i + 2);
        if (end > 0) {
          final name = placeholder(tokens.length);
          tokens[name] = text.substring(i, end + 2);
          out.write('"$name"');
          i = end + 2;
          continue;
        }
      }
      out.write(c);
      i++;
    }
    try {
      return (doc: OdooJsonDoc(jsonDecode(out.toString()), tokens), error: null);
    } on FormatException catch (e) {
      return (doc: null, error: e.message);
    }
  }

  /// [value] as JSON text with every placeholder written back as the token it stands for. [indent] pretty-prints it.
  String encode(Object? value, {bool indent = true}) {
    var text = indent ? const JsonEncoder.withIndent('  ').convert(value) : jsonEncode(value);
    tokens.forEach((name, token) {
      text = text.replaceAll('"$name"', token);
    });
    // A list that holds only a token (`"ids": [{{recordId}}]`) reads better in one piece than on three lines.
    return indent ? text.replaceAllMapped(RegExp(r'\[\s*(\{\{[^{}]+\}\})\s*\]'), (m) => '[${m[1]}]') : text;
  }

  /// The document as text.
  String toText({bool indent = true}) => encode(value, indent: indent);

  /// The token a placeholder stands for, or null for any other value.
  String? tokenOf(Object? v) => v is String ? tokens[v] : null;

  /// The same document with [tokens] added (a value taken from another document carries its placeholders along).
  OdooJsonDoc withTokens(Map<String, String> more) => OdooJsonDoc(value, {...tokens, ...more});
}
