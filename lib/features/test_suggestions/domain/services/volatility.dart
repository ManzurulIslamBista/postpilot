import 'field_path.dart';
import 'value_formats.dart';

/// Tells values that change by themselves (ids, timestamps, tokens, counters, random values) from the ones a
/// test may compare exactly. It looks at the field's name and at what the value looks like; a second response
/// (see `StabilityProbe`) is the stronger evidence, this is what is known from one.
abstract final class Volatility {
  /// Words in a field name that mark it as one that changes on its own.
  static const _volatileWords = {
    'id', 'ids', 'uuid', 'guid', 'uid', 'token', 'jwt', 'nonce', 'signature', 'sig', 'hash', 'checksum', 'etag',
    'cursor', 'session', 'trace', 'correlation', 'random', 'rand', 'counter', 'count', 'total', 'seq', 'sequence',
    'timestamp', 'timestamps', 'ts', 'time', 'date', 'datetime', 'created', 'updated', 'modified', 'deleted',
    'expires', 'expiry', 'epoch', 'elapsed', 'uptime', 'latency', 'ago', 'now', 'otp', 'at',
  };

  static final _camelBoundary = RegExp(r'([a-z0-9])([A-Z])');
  static final _wordSplit = RegExp(r'[^A-Za-z0-9]+');

  /// The lower-case words of a field name: `createdAt` and `created_at` are both `created`, `at`.
  static List<String> words(String key) => [
        for (final w in key.replaceAllMapped(_camelBoundary, (m) => '${m[1]} ${m[2]}').split(_wordSplit))
          if (w.isNotEmpty) w.toLowerCase(),
      ];

  /// Why the field called [key] holding [value] is expected to change, or null when it is not.
  static String? reason(String key, Object? value) {
    final named = words(key).firstWhere(_volatileWords.contains, orElse: () => '');
    if (named.isNotEmpty) return _nameReason(named);
    return _valueReason(value);
  }

  /// [reason] for the field at [path] (its own name).
  static String? reasonAt(String path, Object? value) => reason(FieldPath.lastKey(path), value);

  static bool isVolatile(String key, Object? value) => reason(key, value) != null;

  static String _nameReason(String word) => switch (word) {
        'id' || 'ids' || 'uuid' || 'guid' || 'uid' => 'it is an id',
        'token' || 'jwt' || 'nonce' || 'signature' || 'sig' || 'otp' || 'hash' || 'checksum' || 'etag' || 'cursor' => 'it is a token or hash',
        'count' || 'total' || 'counter' || 'seq' || 'sequence' => 'it is a counter',
        'random' || 'rand' => 'it is random',
        'session' || 'trace' || 'correlation' => 'it identifies one session or request',
        _ => 'it is a date or time',
      };

  static String? _valueReason(Object? value) {
    if (value is String) {
      final kind = ValueFormats.of(value);
      return switch (kind) {
        ValueFormat.uuid => 'it looks like a UUID',
        ValueFormat.dateTime || ValueFormat.date => 'it looks like a date or time',
        ValueFormat.jwt || ValueFormat.opaqueId => 'it looks like a token or id',
        _ => null,
      };
    }
    if (value is num) {
      final whole = value is int || (value.isFinite && value == value.truncateToDouble());
      if (!whole) return null;
      final n = value.toDouble().abs();
      // 2^53: past it a number cannot hold every integer, which is what a generated id looks like.
      if (n >= 9007199254740992) return 'it is a very large number, like a generated id';
      // Unix time in seconds, milliseconds or microseconds, between the years 2000 and 2100.
      if ((n >= 946684800 && n <= 4102444800) ||
          (n >= 946684800000 && n <= 4102444800000) ||
          (n >= 946684800000000 && n <= 4102444800000000)) {
        return 'it looks like a Unix timestamp';
      }
    }
    return null;
  }
}
