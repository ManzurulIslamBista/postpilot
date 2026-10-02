import 'dart:convert';

/// A decoded JSON Web Token (header, claims, the times in them). The signature
/// is shown, never verified: that needs the secret.
final class JwtInfo {
  final Map<String, dynamic> header;
  final Map<String, dynamic> payload;
  final String signature;

  const JwtInfo({required this.header, required this.payload, required this.signature});

  DateTime? _time(String claim) {
    final v = payload[claim];
    return v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000, isUtc: true) : null;
  }

  DateTime? get issuedAt => _time('iat');
  DateTime? get expiresAt => _time('exp');
  DateTime? get notBefore => _time('nbf');

  bool isExpired(DateTime now) => expiresAt != null && !expiresAt!.isAfter(now.toUtc());
}

abstract final class JwtDecoder {
  static final _jwt = RegExp(r'[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]*');

  /// `null` unless [token] (optionally prefixed `Bearer `) is three base64url
  /// parts whose first two are JSON objects.
  static JwtInfo? tryDecode(String token) {
    var t = token.trim();
    if (t.toLowerCase().startsWith('bearer ')) t = t.substring(7).trim();
    final parts = t.split('.');
    if (parts.length != 3) return null;
    try {
      final header = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))));
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (header is! Map<String, dynamic> || payload is! Map<String, dynamic>) return null;
      return JwtInfo(header: header, payload: payload, signature: parts[2]);
    } catch (_) {
      return null;
    }
  }

  /// Every JWT found in the string values of [json]: `path` → token.
  static Map<String, String> findIn(Object? json, {String path = ''}) {
    final found = <String, String>{};
    void walk(Object? value, String at) {
      if (found.length >= 20) return;
      if (value is String) {
        final m = _jwt.firstMatch(value);
        if (m != null && tryDecode(m[0]!) != null) found[at.isEmpty ? r'$' : at] = m[0]!;
      } else if (value is Map) {
        value.forEach((k, v) => walk(v, at.isEmpty ? '$k' : '$at.$k'));
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          walk(value[i], '$at[$i]');
        }
      }
    }

    walk(json, path);
    return found;
  }
}

/// A Unix timestamp read as a date.
final class EpochGuess {
  final DateTime utc;
  final String unit;
  const EpochGuess(this.utc, this.unit);
}

abstract final class EpochConverter {
  /// 2001..2286 in seconds, or the same range in milliseconds / microseconds.
  /// Anything else is a count, an id or a price, not a time.
  static EpochGuess? guess(num value) {
    if (value is double && value != value.truncateToDouble()) return null;
    final v = value.toInt();
    if (v >= 1000000000 && v < 10000000000) {
      return EpochGuess(DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true), 'seconds');
    }
    if (v >= 1000000000000 && v < 10000000000000) {
      return EpochGuess(DateTime.fromMillisecondsSinceEpoch(v, isUtc: true), 'milliseconds');
    }
    if (v >= 1000000000000000 && v < 10000000000000000) {
      return EpochGuess(DateTime.fromMicrosecondsSinceEpoch(v, isUtc: true), 'microseconds');
    }
    return null;
  }

  /// Numbers in [json] that read as timestamps, only where the key says time
  /// (`created_at`, `exp`, `timestamp`, `date`...) to avoid labelling every big id.
  static List<({String path, num value, EpochGuess guess})> findIn(Object? json) {
    final out = <({String path, num value, EpochGuess guess})>[];
    final timeKey = RegExp(r'(time|date|_at$|At$|^exp$|^iat$|^nbf$|created|updated|expires|ts$)', caseSensitive: false);
    void walk(Object? value, String at, String key) {
      if (out.length >= 50) return;
      if (value is num) {
        final g = timeKey.hasMatch(key) ? guess(value) : null;
        if (g != null) out.add((path: at, value: value, guess: g));
      } else if (value is Map) {
        value.forEach((k, v) => walk(v, at.isEmpty ? '$k' : '$at.$k', '$k'));
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          walk(value[i], '$at[$i]', key);
        }
      }
    }

    walk(json, '', '');
    return out;
  }
}

/// One interpretation of a pasted string.
final class DecodeResult {
  final String kind;
  final String output;
  const DecodeResult(this.kind, this.output);
}

/// Tries each common encoding on [input] and returns every one that makes
/// sense, so the "Decode" tab can just show what applies.
abstract final class QuickDecoder {
  static List<DecodeResult> decodeAll(String input) {
    final text = input.trim();
    if (text.isEmpty) return const [];
    final results = <DecodeResult>[];

    final jwt = JwtDecoder.tryDecode(text);
    if (jwt != null) {
      const enc = JsonEncoder.withIndent('  ');
      results.add(DecodeResult('JWT header', enc.convert(jwt.header)));
      results.add(DecodeResult('JWT payload', enc.convert(jwt.payload)));
    }

    final number = num.tryParse(text);
    if (number != null) {
      final g = EpochConverter.guess(number);
      if (g != null) {
        results.add(DecodeResult('Unix time (${g.unit})', '${g.utc.toIso8601String()}\n${g.utc.toLocal()} (local)'));
      }
    }

    final parsedDate = DateTime.tryParse(text);
    if (parsedDate != null && number == null) {
      results.add(DecodeResult(
        'Date to Unix time',
        'seconds: ${parsedDate.millisecondsSinceEpoch ~/ 1000}\nmilliseconds: ${parsedDate.millisecondsSinceEpoch}',
      ));
    }

    if (jwt == null && text.length >= 4 && RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$').hasMatch(text)) {
      try {
        final bytes = base64Url.decode(base64Url.normalize(text.replaceAll('+', '-').replaceAll('/', '_')));
        final decoded = utf8.decode(bytes);
        if (!decoded.runes.any((r) => r < 9 || (r > 13 && r < 32))) results.add(DecodeResult('Base64', decoded));
      } catch (_) {}
    }

    if (text.contains('%') || text.contains('+')) {
      try {
        final decoded = Uri.decodeQueryComponent(text);
        if (decoded != text) results.add(DecodeResult('URL-encoded', decoded));
      } catch (_) {}
    }

    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        results.add(DecodeResult('JSON (formatted)', const JsonEncoder.withIndent('  ').convert(jsonDecode(text))));
      } catch (_) {}
    }

    if (text.contains(r'\u') || text.contains(r'\n') || text.contains(r'\"')) {
      try {
        final unescaped = jsonDecode('"${text.replaceAll('"', r'\"').replaceAll(r'\\"', r'\"')}"') as String;
        if (unescaped != text) results.add(DecodeResult('Unescaped string', unescaped));
      } catch (_) {}
    }

    results.add(DecodeResult('Base64 of this text', base64.encode(utf8.encode(text))));
    return results;
  }
}
