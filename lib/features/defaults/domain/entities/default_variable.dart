/// A `{{variable}}` a folder passes down to the requests below it. Folder
/// variables sit between the collection's variables and the active
/// environment (see `BuildVariableResolverUseCase`).
///
/// [id] is session-only, purely so an editor keeps a stable `ValueKey` per row
/// (same reason as `KeyValueItem.id`); it is never persisted and not part of
/// equality.
final class DefaultVariable {
  static int _nextId = 0;

  final int id;
  final String key;
  final String value;

  /// A secret's value stays out of the hover card and is kept out of a
  /// workspace file that is shared (see `SecretSplitter`).
  final bool isSecret;
  final bool enabled;

  DefaultVariable({int? id, required this.key, this.value = '', this.isSecret = false, this.enabled = true})
      : id = id ?? _nextId++;

  DefaultVariable copyWith({String? key, String? value, bool? isSecret, bool? enabled}) => DefaultVariable(
        id: id,
        key: key ?? this.key,
        value: value ?? this.value,
        isSecret: isSecret ?? this.isSecret,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is DefaultVariable &&
      other.key == key &&
      other.value == value &&
      other.isSecret == isSecret &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(key, value, isSecret, enabled);
}
