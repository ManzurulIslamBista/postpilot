import 'dart:convert';

import 'secret_names.dart';

/// Blanking of credentials that sit inside free text: the password and the
/// secret query parameters of a URL, secret-named values of a body (JSON, XML
/// and SOAP, GraphQL literal arguments, urlencoded text) and known token shapes
/// in notes. Only the credential value is emptied, everything else stays byte
/// for byte, so a stripped text differs from the original in nothing but secrets.
///
/// Each `blank…` has a matching `restore…`: given the text as stripped
/// (`target`) and the local text that still has its credentials, it puts the
/// local values back into the blanks of `target`, matching by name and by
/// occurrence.
///
/// With a `placeholder`, a blanked value becomes `{{name}}` (for the name the
/// placeholder function returns) instead of nothing, so an exported file still
/// says what has to be filled in.
abstract final class SecretText {
  /// `scheme://user:password@`: group 1 is everything before the colon.
  static final _userInfo = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*://[^/?#@:]*):([^/?#@]*)@');

  /// A `"key": "value"` pair of a JSON text: the quoted key, the separator, the string value.
  static final _jsonPair = RegExp(r'("(?:[^"\\]|\\.)*")(\s*:\s*)"((?:[^"\\]|\\.)*)"');

  /// A `"key": 1234` pair of a JSON text: the quoted key, the separator, the number.
  static final _jsonNumberPair = RegExp(r'("(?:[^"\\]|\\.)*")(\s*:\s*)(-?\d+(?:\.\d+)?)(?![\w.])');

  /// `name: "literal"` and `name="literal"` with a bare name: GraphQL
  /// arguments, XML attributes, JavaScript objects, `.env` files.
  static final _literal = RegExp(
    r'''(?<![\w.$"'\-])([A-Za-z_][\w.\-]*)(\s*[:=]\s*)("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')''',
  );

  /// `<Name attrs>text</Name>`, prefix and CDATA allowed (SOAP `wsse:Password`).
  static final _xml = RegExp(
    r'(<((?:[\w.\-]+:)?[\w.\-]+)(?:\s[^<>]*)?>)((?:<!\[CDATA\[[\s\S]*?\]\]>)|[^<>]*)(</\2\s*>)',
  );

  /// `name=value` of a urlencoded body sent as raw text, an `.env` file or a
  /// query string. The value runs to the next separator and may be empty (a blanked one).
  static final _assignment = RegExp(r'''(?<![\w.%\[\]\-])([A-Za-z_][\w.%\[\]\-]*)=(?:([^&\s"'<>;]+)|(?=[&\s]|$))''');

  /// `Bearer abc…`, `Basic abc…`: an auth scheme and its credential, in a note.
  static final _scheme = RegExp(r'\b(Bearer|Basic|Digest|Token)(\s+)([\w.~+/=\-]{16,})');

  static final _variableName = RegExp(r'[^A-Za-z0-9_.$\-]+');

  static String blankUrl(String url, {String Function(String name)? placeholder}) =>
      _blankUrl(url, placeholder, (value) => SecretNames.hasLiteralSecret(value));

  static String _blankUrl(String url, String Function(String name)? placeholder, bool Function(String value) qualifies) {
    var result = url;
    final info = _userInfo.firstMatch(result);
    if (info != null && qualifies(info.group(2)!)) {
      result = '${info.group(1)}:${_fill('password', placeholder)}@${result.substring(info.end)}';
    }
    return _mapQuery(result, (key, value, nth) {
      final name = _decode(key);
      return SecretNames.isSecretQuery(name) && qualifies(value) ? _fill(name, placeholder) : value;
    });
  }

  static String restoreUrl(String target, String local) {
    var result = target;
    final targetInfo = _userInfo.firstMatch(target);
    final localInfo = _userInfo.firstMatch(local);
    if (targetInfo != null &&
        localInfo != null &&
        targetInfo.group(1) == localInfo.group(1) &&
        targetInfo.group(2)!.isEmpty &&
        localInfo.group(2)!.isNotEmpty) {
      result = '${targetInfo.group(1)}:${localInfo.group(2)}@${target.substring(targetInfo.end)}';
    }

    final localValues = <String, List<String>>{};
    _mapQuery(local, (key, value, nth) {
      (localValues[key] ??= []).add(value);
      return value;
    });
    return _mapQuery(result, (key, value, nth) {
      if (value.isNotEmpty || !SecretNames.isSecretQuery(_decode(key))) return value;
      final options = localValues[key];
      return options != null && nth < options.length ? options[nth] : value;
    });
  }

  // --- bodies ---------------------------------------------------------------

  /// [text] (a raw body, GraphQL query or variables, a response example) with
  /// the value of every secret-named JSON pair, GraphQL or XML attribute
  /// literal, XML element and `name=value` pair emptied. A bare number under a
  /// credential name (`"pin": 1234`) becomes `""`. Values that only reference
  /// `{{variables}}` stay.
  static String blankBody(String text, {String Function(String name)? placeholder}) =>
      _blankBody(text, placeholder, (_) => true);

  /// Puts the credentials [local] has back into the blanks of [target].
  static String restoreBody(String target, String local) {
    if (target.isEmpty || local.isEmpty) return target;
    final targetHits = _hits(target);
    if (targetHits.isEmpty) return target;
    final localByName = <String, List<_Hit>>{};
    for (final hit in _hits(local)) {
      (localByName[hit.name] ??= []).add(hit);
    }
    if (localByName.isEmpty) return target;

    final seen = <String, int>{};
    final out = StringBuffer();
    var pos = 0;
    var changed = false;
    for (final hit in targetHits) {
      final nth = seen[hit.name] = (seen[hit.name] ?? -1) + 1;
      final options = localByName[hit.name];
      if (!hit.isEmpty || options == null || nth >= options.length) continue;
      final source = options[nth];
      if (source.isEmpty || !source.compatibleWith(hit) || !source.qualifies) continue;
      out
        ..write(target.substring(pos, hit.start))
        ..write(source.token);
      pos = hit.end;
      changed = true;
    }
    if (!changed) return target;
    return (out..write(target.substring(pos))).toString();
  }

  /// The JSON-only names of [blankBody] and [restoreBody], kept for callers that predate it.
  static String blankJson(String text) => blankBody(text);
  static String restoreJson(String target, String local) => restoreBody(target, local);

  static String _blankBody(String text, String Function(String name)? placeholder, bool Function(String value) qualifies) {
    if (text.isEmpty) return text;
    final out = StringBuffer();
    var pos = 0;
    var changed = false;
    for (final hit in _hits(text)) {
      if (hit.isEmpty || !hit.qualifies || !qualifies(hit.content)) continue;
      out
        ..write(text.substring(pos, hit.start))
        ..write(placeholder == null ? hit.empty : hit.wrap(_fill(hit.name, placeholder)));
      pos = hit.end;
      changed = true;
    }
    if (!changed) return text;
    return (out..write(text.substring(pos))).toString();
  }

  // --- notes ----------------------------------------------------------------

  /// A description or other prose, with the credentials that are unmistakable
  /// removed: known token shapes (JWT, `ghp_…`, `sk_live_…`), a `Bearer …`
  /// value, the password of a `user:pass@host` URL and secret-named pairs
  /// whose value looks generated. Ordinary prose that mentions a password or
  /// shows a `YOUR_API_KEY` placeholder stays untouched.
  static String blankNote(String text) {
    if (text.isEmpty) return text;
    var result = _blankBody(text, null, SecretNames.looksLikeCredential);
    result = result.replaceAllMapped(
      RegExp(r'([a-zA-Z][a-zA-Z0-9+.\-]*://[^/?#@:\s]*):([^/?#@\s]+)@'),
      (m) => SecretNames.looksLikeCredential(m[2]!) ? '${m[1]}:@' : m[0]!,
    );
    result = result.replaceAllMapped(_scheme, (m) => SecretNames.looksLikeCredential(m[3]!) ? '${m[1]}${m[2]}' : m[0]!);
    final known = SecretNames.knownTokens(result).toList();
    if (known.isEmpty) return result;
    final out = StringBuffer();
    var pos = 0;
    for (final m in known) {
      out.write(result.substring(pos, m.start));
      pos = m.end;
    }
    return (out..write(result.substring(pos))).toString();
  }

  /// Short text that quotes a body, such as what an assertion expects it to
  /// contain: [blankBody] and [blankNote] together.
  static String blankSnippet(String text) => blankNote(blankBody(text));

  /// [target] (a stripped snippet) with [local]'s credentials back: all of them
  /// when nothing else differs, else the ones a name says belong to a place.
  static String restoreSnippet(String target, String local) =>
      blankSnippet(local) == target ? local : restoreBody(target, local);

  /// [target] (a stripped note) with [local]'s credentials back, but only when
  /// nothing else differs: a note is prose, so credentials cannot be put back
  /// into text somebody else has edited.
  static String restoreNote(String target, String local) => blankNote(local) == target ? local : target;

  // --- URL helpers ----------------------------------------------------------

  /// [url] with the value of every `key=value` query parameter replaced by
  /// [replace]`(rawKey, rawValue, occurrenceOfThatKey)`. The rest is untouched.
  static String _mapQuery(String url, String Function(String key, String value, int nth) replace) {
    final hash = url.indexOf('#');
    final beforeFragment = hash < 0 ? url : url.substring(0, hash);
    final fragment = hash < 0 ? '' : url.substring(hash);
    final question = beforeFragment.indexOf('?');
    if (question < 0) return url;

    final seen = <String, int>{};
    final params = [
      for (final part in beforeFragment.substring(question + 1).split('&')) _mapParam(part, seen, replace),
    ];
    return '${beforeFragment.substring(0, question + 1)}${params.join('&')}$fragment';
  }

  static String _mapParam(String part, Map<String, int> seen, String Function(String, String, int) replace) {
    final equals = part.indexOf('=');
    if (equals < 0) return part;
    final key = part.substring(0, equals);
    final nth = seen[key] = (seen[key] ?? -1) + 1;
    return '$key=${replace(key, part.substring(equals + 1), nth)}';
  }

  static String _decode(String component) {
    try {
      return Uri.decodeQueryComponent(component);
    } on FormatException {
      return component;
    } on ArgumentError {
      return component;
    }
  }

  /// `{{name}}` for [name] (made a legal variable name), or nothing without a placeholder.
  static String _fill(String name, String Function(String name)? placeholder) {
    if (placeholder == null) return '';
    final variable = placeholder(name).replaceAll(_variableName, '_');
    return '{{${variable.isEmpty ? 'secret' : variable}}}';
  }

  // --- the places of a body that can hold a credential ---------------------------

  /// Every place of [text] whose name says it holds a credential, in text
  /// order and without overlaps (the first of two overlapping places wins).
  /// Blank places are included: they keep the occurrence numbers of a stripped
  /// text and of the original aligned.
  static List<_Hit> _hits(String text) {
    final all = <_Hit>[];
    for (final m in _jsonPair.allMatches(text)) {
      final start = m.start + m.group(1)!.length + m.group(2)!.length;
      all.add(_Hit(_Kind.jsonString, _jsonKey(m.group(1)!), start, m.end, text.substring(start, m.end)));
    }
    for (final m in _jsonNumberPair.allMatches(text)) {
      final start = m.start + m.group(1)!.length + m.group(2)!.length;
      all.add(_Hit(_Kind.jsonNumber, _jsonKey(m.group(1)!), start, m.end, m.group(3)!));
    }
    for (final m in _literal.allMatches(text)) {
      final start = m.start + m.group(1)!.length + m.group(2)!.length;
      all.add(_Hit(_Kind.literal, m.group(1)!, start, m.end, m.group(3)!));
    }
    for (final m in _xml.allMatches(text)) {
      final start = m.start + m.group(1)!.length;
      final name = m.group(2)!;
      all.add(_Hit(_Kind.xml, name.substring(name.indexOf(':') + 1), start, start + m.group(3)!.length, m.group(3)!));
    }
    for (final m in _assignment.allMatches(text)) {
      final value = m.group(2) ?? '';
      all.add(_Hit(_Kind.assignment, _decode(m.group(1)!), m.end - value.length, m.end, value));
    }

    all.removeWhere((hit) => !hit.nameQualifies);
    all.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : b.end.compareTo(a.end);
    });
    final hits = <_Hit>[];
    var lastEnd = 0;
    for (final hit in all) {
      if (hit.start < lastEnd) continue;
      hits.add(hit);
      lastEnd = hit.end;
    }
    return hits;
  }

  static String _jsonKey(String quoted) {
    try {
      final key = jsonDecode(quoted);
      if (key is String) return key;
    } on FormatException {
      // fall through to the raw text
    }
    return quoted.substring(1, quoted.length - 1);
  }
}

enum _Kind { jsonString, jsonNumber, literal, xml, assignment }

/// The value of one name in a body: [token] is the text from [start] to [end].
final class _Hit {
  final _Kind kind;
  final String name;
  final int start;
  final int end;
  final String token;

  const _Hit(this.kind, this.name, this.start, this.end, this.token);

  bool get _quoted => kind == _Kind.jsonString || kind == _Kind.literal;

  /// The value without its quotes.
  String get content => _quoted ? token.substring(1, token.length - 1) : token;

  /// What blanking leaves in the token's place.
  String get empty => switch (kind) {
        _Kind.jsonString || _Kind.jsonNumber => '""',
        _Kind.literal => '${token[0]}${token[0]}',
        _Kind.xml || _Kind.assignment => '',
      };

  bool get isEmpty => token == empty;

  /// [inner] as a value of this kind.
  String wrap(String inner) => switch (kind) {
        _Kind.jsonString || _Kind.jsonNumber => '"$inner"',
        _Kind.literal => '${token[0]}$inner${token[0]}',
        _Kind.xml || _Kind.assignment => inner,
      };

  /// Whether the name alone says this is a credential. A bare `key` always
  /// takes part, so occurrence numbers line up; [qualifies] then looks at the value.
  bool get nameQualifies => switch (kind) {
        _Kind.jsonNumber => SecretNames.isNumericSecretKey(name),
        _Kind.xml => SecretNames.looksSecretKey(name),
        _ => SecretNames.looksSecretKey(name) || _isBareKey,
      };

  bool get _isBareKey {
    final parts = SecretNames.words(name);
    return parts.length == 1 && parts.single == 'key';
  }

  /// Whether this value is one to blank or to restore.
  bool get qualifies {
    if (kind == _Kind.jsonNumber) return true;
    final value = content;
    if (value.trim().isEmpty || !SecretNames.hasLiteralSecret(value)) return false;
    return !_isBareKey || SecretNames.looksLikeCredential(value);
  }

  /// [other] (a blank place of a stripped text) can take this value.
  bool compatibleWith(_Hit other) => kind == other.kind || (kind == _Kind.jsonNumber && other.kind == _Kind.jsonString);
}
