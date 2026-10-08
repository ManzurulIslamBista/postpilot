/// "Who is asking": a named set of variable values a matrix column puts on top of its environment, e.g. `admin` with
/// `token = ...`, `user` with another token, or `anonymous` with the auth variables cleared. It reaches a request the
/// way a collection run's data row does: as the top variable scope, so it beats a variable of the same name and every
/// `{{reference}}` to it.
///
/// An empty value *clears* the variable: it stays defined (so the run is not blocked as "undefined variable") but
/// resolves to nothing, which is how `anonymous` sends a request without its credentials.
///
/// Pure Dart, so the command line shares it.
final class MatrixIdentity {
  final String id;
  final String name;

  /// Variable name to value; an empty value clears the variable.
  final Map<String, String> variables;

  const MatrixIdentity({required this.id, required this.name, this.variables = const {}});

  /// The names this identity clears (their value is empty).
  Set<String> get cleared => {
        for (final e in variables.entries)
          if (e.value.isEmpty) e.key,
      };

  /// Every variable it sets is cleared: a caller with no credentials at all.
  bool get isAnonymous => variables.isNotEmpty && variables.values.every((v) => v.isEmpty);

  MatrixIdentity copyWith({String? name, Map<String, String>? variables}) =>
      MatrixIdentity(id: id, name: name ?? this.name, variables: variables ?? this.variables);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'variables': variables};

  /// Reads one saved identity; null when [json] is not one (a damaged value is dropped, never thrown).
  static MatrixIdentity? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final raw = json['variables'];
    return MatrixIdentity(
      id: id,
      name: name,
      variables: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String && (e.key as String).trim().isNotEmpty) (e.key as String).trim(): '${e.value ?? ''}',
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MatrixIdentity &&
      other.id == id &&
      other.name == name &&
      other.variables.length == variables.length &&
      other.variables.entries.every((e) => variables[e.key] == e.value);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAllUnordered(variables.entries.map((e) => Object.hash(e.key, e.value))));

  @override
  String toString() => 'MatrixIdentity($name, ${variables.keys.join(', ')})';
}
