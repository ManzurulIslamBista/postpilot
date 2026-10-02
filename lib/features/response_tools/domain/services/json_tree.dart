/// Builds the dot/bracket paths that `JsonPathResolver` reads back, so a path
/// copied from the JSON tree can go straight into an assertion or extractor.
abstract final class JsonPaths {
  static final _plainKey = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  static String key(String parent, String key) {
    if (_plainKey.hasMatch(key)) return parent.isEmpty ? key : '$parent.$key';
    final quote = key.contains('"') ? "'" : '"';
    return '$parent[$quote$key$quote]';
  }

  static String index(String parent, int index) => '$parent[$index]';
}

enum JsonNodeKind { object, array, string, number, boolean, nullValue }

/// One position in a decoded JSON document, with children created on demand
/// so a large response opens instantly and only expanded branches cost anything.
final class JsonNode {
  final String label;
  final String path;
  final Object? value;

  const JsonNode({required this.label, required this.path, required this.value});

  factory JsonNode.root(Object? json) => JsonNode(label: r'$', path: '', value: json);

  JsonNodeKind get kind => switch (value) {
        Map<dynamic, dynamic>() => JsonNodeKind.object,
        List<dynamic>() => JsonNodeKind.array,
        String() => JsonNodeKind.string,
        num() => JsonNodeKind.number,
        bool() => JsonNodeKind.boolean,
        _ => JsonNodeKind.nullValue,
      };

  bool get isContainer => kind == JsonNodeKind.object || kind == JsonNodeKind.array;

  int get childCount => switch (value) {
        final Map<dynamic, dynamic> m => m.length,
        final List<dynamic> l => l.length,
        _ => 0,
      };

  List<JsonNode> get children => switch (value) {
        final Map<dynamic, dynamic> m => [
            for (final e in m.entries)
              JsonNode(label: '${e.key}', path: JsonPaths.key(path, '${e.key}'), value: e.value),
          ],
        final List<dynamic> l => [
            for (var i = 0; i < l.length; i++) JsonNode(label: '[$i]', path: JsonPaths.index(path, i), value: l[i]),
          ],
        _ => const [],
      };

  /// What the value looks like on one line: `{3}`, `[12]`, `"text"`, `42`.
  String get preview => switch (kind) {
        JsonNodeKind.object => '{$childCount}',
        JsonNodeKind.array => '[$childCount]',
        JsonNodeKind.string => '"${_clip(value as String)}"',
        JsonNodeKind.nullValue => 'null',
        _ => '$value',
      };

  static String _clip(String s) {
    final single = s.replaceAll('\n', r'\n');
    return single.length > 80 ? '${single.substring(0, 80)}…' : single;
  }

  /// Paths of every node whose label, path or scalar value contains [query]
  /// (case-insensitive), capped so a one-letter query on a huge body stays cheap.
  static List<String> search(Object? json, String query, {int limit = 200}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits = <String>[];
    void walk(JsonNode node) {
      if (hits.length >= limit) return;
      final scalarMatch = !node.isContainer && '${node.value}'.toLowerCase().contains(q);
      final keyMatch = node.path.isNotEmpty && node.label.toLowerCase().contains(q);
      if (scalarMatch || keyMatch) hits.add(node.path);
      for (final child in node.children) {
        walk(child);
        if (hits.length >= limit) return;
      }
    }

    walk(JsonNode.root(json));
    return hits;
  }
}
