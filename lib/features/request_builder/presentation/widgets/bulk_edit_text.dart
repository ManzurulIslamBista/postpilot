import 'dart:convert';
import '../../domain/entities/key_value_item.dart';

/// The text form of a key/value list behind `KeyValueEditor`'s "Bulk edit"
/// mode: one `key:value` per line, `//` in front of a disabled row. A line is
/// split at its first colon and both halves are trimmed; blank lines are
/// ignored, and so are rows that are entirely empty.
abstract final class BulkEditText {
  static const _disabledMarker = '//';

  static String serialize(List<KeyValueItem> items) => [
        for (final item in items)
          if (!_isBlank(item)) _line(item),
      ].join('\n');

  /// Reads [text] back into rows, reusing what [previous] (the rows [text] was
  /// made from, or last parsed into) already holds:
  ///
  /// 1. A line that is exactly what an existing row serializes to *is* that
  ///    row, wherever it moved. This keeps rows the format cannot spell
  ///    losslessly (a colon in the key, a newline in the value, padding)
  ///    intact when they are not touched.
  /// 2. Otherwise the row is rebuilt from the text, keeping the id of the
  ///    previous row at the same position when the key is unchanged.
  /// 3. Otherwise it gets a fresh id.
  static List<KeyValueItem> parse(String text, {List<KeyValueItem> previous = const []}) {
    final lines = <_Line>[
      for (final raw in const LineSplitter().convert(text)) ?_read(raw),
    ];
    final old = [
      for (final item in previous)
        if (!_isBlank(item)) item,
    ];
    final untouched = <String, List<KeyValueItem>>{};
    for (final item in old) {
      untouched.putIfAbsent(_line(item), () => []).add(item);
    }

    final claimed = <int>{};
    final result = List<KeyValueItem?>.filled(lines.length, null);
    for (var i = 0; i < lines.length; i++) {
      final bucket = untouched[lines[i].raw];
      if (bucket == null || bucket.isEmpty) continue;
      final item = bucket.removeAt(0);
      claimed.add(item.id);
      result[i] = item;
    }
    for (var i = 0; i < lines.length; i++) {
      if (result[i] != null) continue;
      final line = lines[i];
      final sameSlot = i < old.length ? old[i] : null;
      if (sameSlot != null && !claimed.contains(sameSlot.id) && sameSlot.key == line.key) {
        claimed.add(sameSlot.id);
        result[i] = sameSlot.copyWith(value: line.value, enabled: line.enabled);
      } else {
        result[i] = KeyValueItem(key: line.key, value: line.value, enabled: line.enabled);
      }
    }
    return [for (final item in result) item!];
  }

  static bool sameRows(List<KeyValueItem> a, List<KeyValueItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id || x.key != y.key || x.value != y.value || x.enabled != y.enabled) return false;
    }
    return true;
  }

  static bool _isBlank(KeyValueItem item) => item.key.isEmpty && item.value.isEmpty;

  static String _line(KeyValueItem item) =>
      '${item.enabled ? '' : _disabledMarker}${_oneLine(item.key)}:${_oneLine(item.value)}';

  // A line break inside a key or value would otherwise read back as two rows.
  static String _oneLine(String text) => text.replaceAll(RegExp(r'\r\n|[\r\n]'), ' ');

  static _Line? _read(String raw) {
    var rest = raw.trimLeft();
    final enabled = !rest.startsWith(_disabledMarker);
    if (!enabled) rest = rest.substring(_disabledMarker.length);
    final colon = rest.indexOf(':');
    final key = (colon == -1 ? rest : rest.substring(0, colon)).trim();
    final value = colon == -1 ? '' : rest.substring(colon + 1).trim();
    if (key.isEmpty && value.isEmpty) return null;
    return _Line(raw, key, value, enabled);
  }
}

final class _Line {
  final String raw;
  final String key;
  final String value;
  final bool enabled;

  const _Line(this.raw, this.key, this.value, this.enabled);
}
