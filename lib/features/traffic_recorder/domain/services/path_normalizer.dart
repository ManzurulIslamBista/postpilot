/// A request path with its changing parts made into `{{variables}}`.
final class NormalizedPath {
  /// `/users/{{userId}}/posts`, ready to follow `{{baseUrl}}`.
  final String template;

  /// The values the variables had in the path that was normalised, in path order.
  final List<PathVariable> variables;

  const NormalizedPath(this.template, this.variables);

  /// The template as a request name shows it: `/users/{userId}/posts`.
  String get display => template.replaceAllMapped(RegExp(r'\{\{([^{}]+)\}\}'), (m) => '{${m[1]}}');
}

final class PathVariable {
  final String name;
  final String value;
  const PathVariable(this.name, this.value);
}

/// Turns `/users/42/posts/9` into `/users/{{userId}}/posts/{{postId}}`, so a hundred calls to the same endpoint become one
/// request. A segment is an identifier when it is a number, a UUID or a long run of hex digits (an ObjectId, a hash); the
/// variable is named after the segment before it (`users` becomes `userId`), or `id` / `uuid` when there is none.
abstract final class PathNormalizer {
  static final _numeric = RegExp(r'^\d+$');
  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final _longHex = RegExp(r'^[0-9a-fA-F]{16,}$');

  /// [path] is the path alone (no query), as the app sent it.
  static NormalizedPath normalize(String path) {
    final out = <String>[];
    final variables = <PathVariable>[];
    final used = <String>{};
    String? previous;
    for (final segment in path.split('/')) {
      final isUuid = _uuid.hasMatch(segment);
      if (segment.isEmpty || !(isUuid || _numeric.hasMatch(segment) || _longHex.hasMatch(segment))) {
        out.add(segment);
        if (segment.isNotEmpty) previous = segment;
        continue;
      }
      var name = _nameFor(previous, isUuid);
      for (var n = 2; used.contains(name); n++) {
        name = '${_nameFor(previous, isUuid)}$n';
      }
      used.add(name);
      variables.add(PathVariable(name, segment));
      out.add('{{$name}}');
      previous = null;
    }
    return NormalizedPath(out.join('/'), variables);
  }

  /// `users` -> `userId`, `blog-posts` -> `blogPostId`, nothing usable -> `id`.
  static String _nameFor(String? previous, bool uuid) {
    final suffix = uuid ? 'Uuid' : 'Id';
    final base = previous == null ? null : singularCamel(previous);
    return base == null ? suffix.toLowerCase() : '$base$suffix';
  }

  /// [word] as a singular lowerCamelCase identifier part; null when it holds no letters or starts with a digit.
  static String? singularCamel(String word) {
    final parts = [
      for (final p in word.split(RegExp(r'[^A-Za-z0-9]+')))
        if (p.isNotEmpty) p,
    ];
    if (parts.isEmpty || !RegExp(r'^[A-Za-z]').hasMatch(parts.first)) return null;
    parts[parts.length - 1] = _singular(parts.last);
    final camel = StringBuffer(parts.first[0].toLowerCase() + parts.first.substring(1));
    for (final p in parts.skip(1)) {
      camel.write(p[0].toUpperCase() + p.substring(1));
    }
    return camel.toString();
  }

  static String _singular(String word) {
    final w = word;
    if (w.length > 3 && w.toLowerCase().endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 4 && w.toLowerCase().endsWith('sses')) return w.substring(0, w.length - 2);
    final lower = w.toLowerCase();
    if (w.length > 1 && lower.endsWith('s') && !lower.endsWith('ss') && !lower.endsWith('us') && !lower.endsWith('is')) {
      return w.substring(0, w.length - 1);
    }
    return w;
  }
}
