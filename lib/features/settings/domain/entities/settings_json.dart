import 'dart:convert';

/// Lenient readers for the stored settings JSON: a missing key, a value of
/// the wrong type, or a number out of range falls back instead of failing, so
/// a hand-edited or older document never blocks the app from starting.
abstract final class SettingsJson {
  static Map<String, dynamic> decodeObject(String? source) {
    if (source == null || source.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(source);
      return decoded is Map ? decoded.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }

  static Map<String, dynamic> objectOf(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : const {};

  static bool boolOr(Object? value, bool fallback) => value is bool ? value : fallback;

  static bool? boolOrNull(Object? value) => value is bool ? value : null;

  static String stringOr(Object? value, String fallback) => value is String ? value : fallback;

  static int intOr(Object? value, int fallback, {required int min, required int max}) =>
      intOrNull(value, min: min, max: max) ?? fallback;

  /// A number below [min] is corrupt (a negative timeout must not become "no
  /// timeout"), so it reads as absent; one above [max] is capped.
  static int? intOrNull(Object? value, {required int min, required int max}) {
    if (value is! num || !value.isFinite) return null;
    final number = value.toInt();
    if (number < min) return null;
    return number > max ? max : number;
  }

  static T enumOr<T extends Enum>(Object? value, List<T> values, T fallback) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    return fallback;
  }
}
