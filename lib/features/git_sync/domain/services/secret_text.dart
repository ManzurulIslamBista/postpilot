import 'dart:convert';

import 'secret_names.dart';

/// Blanking of credentials that sit inside free text: the password and the
/// secret query parameters of a URL, and secret-named string values of a JSON
/// text. Only the credential value is emptied, everything else stays byte for
/// byte, so a stripped text differs from the original in nothing but secrets.
///
/// Each `blank…` has a matching `restore…`: given the text as stripped
/// (`target`) and the local text that still has its credentials, it puts the
/// local values back into the blanks of `target`, matching by name and by
/// occurrence.
abstract final class SecretText {
  /// `scheme://user:password@`: group 1 is everything before the colon.
  static final _userInfo = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*://[^/?#@:]*):([^/?#@]*)@');

  /// A `"key": "value"` pair of a JSON text: the quoted key, the separator, the string value.
  static final _jsonPair = RegExp(r'("(?:[^"\\]|\\.)*")(\s*:\s*)"((?:[^"\\]|\\.)*)"');

  static String blankUrl(String url) {
    var result = url;
    final info = _userInfo.firstMatch(result);
    if (info != null && SecretNames.hasLiteralSecret(info.group(2)!)) {
      result = '${info.group(1)}:@${result.substring(info.end)}';
    }
    return _mapQuery(
      result,
      (key, value, nth) => SecretNames.isSecretQuery(_decode(key)) && SecretNames.hasLiteralSecret(value) ? '' : value,
    );
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

  static String blankJson(String text) => text.replaceAllMapped(_jsonPair, (m) {
        final blank = SecretNames.looksSecretKey(_jsonKey(m.group(1)!)) && SecretNames.hasLiteralSecret(m.group(3)!);
        return blank ? '${m.group(1)}${m.group(2)}""' : m.group(0)!;
      });

  static String restoreJson(String target, String local) {
    final localValues = <String, List<String>>{};
    for (final m in _jsonPair.allMatches(local)) {
      final key = _jsonKey(m.group(1)!);
      if (SecretNames.looksSecretKey(key)) (localValues[key] ??= []).add(m.group(3)!);
    }
    if (localValues.isEmpty) return target;

    final seen = <String, int>{};
    return target.replaceAllMapped(_jsonPair, (m) {
      final key = _jsonKey(m.group(1)!);
      if (!SecretNames.looksSecretKey(key)) return m.group(0)!;
      final nth = seen[key] = (seen[key] ?? -1) + 1;
      final options = localValues[key];
      if (m.group(3)!.isNotEmpty || options == null || nth >= options.length || options[nth].isEmpty) {
        return m.group(0)!;
      }
      return '${m.group(1)}${m.group(2)}"${options[nth]}"';
    });
  }

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
      for (final part in beforeFragment.substring(question + 1).split('&'))
        _mapParam(part, seen, replace),
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
