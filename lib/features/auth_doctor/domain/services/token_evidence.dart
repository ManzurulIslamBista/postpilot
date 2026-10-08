// Pure Dart (no Flutter, no database).
import '../../../documentation/domain/services/secret_masker.dart';

/// How the doctor writes down a credential it looked at: the first four characters and the length, never the value. A
/// value too short for four characters to be harmless shows only its length.
abstract final class TokenEvidence {
  /// Shorter than this, not even the first four characters are shown.
  static const _minLengthForPrefix = 12;

  /// `eyJh… (143 characters)`, `7 characters`, `empty`.
  static String of(String value) {
    final length = value.length;
    if (length == 0) return 'empty';
    if (length < _minLengthForPrefix) return '$length character${length == 1 ? '' : 's'}';
    return '${value.substring(0, 4)}… ($length characters)';
  }

  /// A header value with its credential reduced to [of]: `Bearer eyJh… (143 characters)`.
  static String ofHeader(String value) {
    final match = RegExp(r'^(\S+)\s+(\S.*)$', dotAll: true).firstMatch(value.trim());
    if (match == null) return of(value.trim());
    return '${match[1]} ${of(match[2]!)}';
  }

  /// A piece of text the server wrote, safe to quote: one line, clipped, with anything that looks like a credential
  /// masked.
  static String quote(String text, {int max = 160}) {
    final oneLine = SecretMasker.maskMessage(text).replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length <= max ? oneLine : '${oneLine.substring(0, max - 1)}…';
  }
}
