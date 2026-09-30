/// A single header/query-param/form-field row.
///
/// [id] is a locally-assigned, session-only identity (never persisted) —
/// its only job is to give editable-list UIs (see `KeyValueEditor`) a
/// stable [ValueKey] per row so Flutter doesn't reuse one row's
/// [TextFormField] state for a different row after an add/remove/rebuild.
/// Without it, list-position-based widget reuse silently leaks or
/// concatenates text between rows — a real bug this class previously had.
final class KeyValueItem {
  static int _nextId = 0;

  final int id;
  final String key;
  final String value;
  final bool enabled;

  KeyValueItem({int? id, required this.key, required this.value, this.enabled = true}) : id = id ?? _nextId++;

  KeyValueItem copyWith({String? key, String? value, bool? enabled}) => KeyValueItem(
        id: id,
        key: key ?? this.key,
        value: value ?? this.value,
        enabled: enabled ?? this.enabled,
      );
}
