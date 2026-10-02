/// Where a `{{variable}}` gets its value from. Declared highest precedence
/// first, matching how a request resolves them.
enum VariableSource {
  /// Built-in `{{$guid}}`-style generators.
  dynamic,
  environment,
  collection,
  global,

  /// No scope holds it, so the token is sent as written.
  unresolved,
}

/// What a `{{name}}` token stands for right now, for showing on hover.
final class VariableInfo {
  final String name;
  final VariableSource source;

  /// The environment's name for [VariableSource.environment]; otherwise null.
  final String? scopeName;

  /// The stored value ([sample] for dynamic variables); null when unresolved.
  final String? value;

  /// A secret's value is never put on screen by a hover.
  final bool isSecret;

  const VariableInfo({
    required this.name,
    required this.source,
    this.scopeName,
    this.value,
    this.isSecret = false,
  });

  const VariableInfo.unresolved(this.name)
      : source = VariableSource.unresolved,
        scopeName = null,
        value = null,
        isSecret = false;

  bool get isResolved => source != VariableSource.unresolved;

  @override
  bool operator ==(Object other) =>
      other is VariableInfo &&
      other.name == name &&
      other.source == source &&
      other.scopeName == scopeName &&
      other.value == value &&
      other.isSecret == isSecret;

  @override
  int get hashCode => Object.hash(name, source, scopeName, value, isSecret);
}
