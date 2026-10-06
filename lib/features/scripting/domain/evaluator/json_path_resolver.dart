/// Resolves dot/bracket paths — `data.items[0].id`, `$.data["a.b"]`,
/// `items.0.id` — against decoded JSON. Deliberately tiny: no wildcards,
/// filters or recursive descent.
abstract final class JsonPathResolver {
  /// `null` when any segment is missing, an index is out of range, or the
  /// path descends into a scalar. A JSON `null` value also resolves to
  /// `null`, so "exists" checks treat it as absent (same as chai's `exist`).
  static Object? resolve(Object? json, String path) {
    var current = json;
    for (final segment in _segments(path.trim())) {
      if (current is Map) {
        final key = segment.toString();
        if (!current.containsKey(key)) return null;
        current = current[key];
      } else if (current is List) {
        final index = segment is int ? segment : int.tryParse(segment as String);
        if (index == null || index < 0 || index >= current.length) return null;
        current = current[index];
      } else {
        return null;
      }
    }
    return current;
  }

  /// The steps of [path] in order: a `String` for a key, an `int` for an index. A leading `$` is dropped. Lets a
  /// caller that writes at a path (the page parameter of a JSON body) walk it the way [resolve] reads it.
  static List<Object> segmentsOf(String path) => _segments(path.trim());

  static List<Object> _segments(String path) {
    final result = <Object>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isNotEmpty) result.add(buffer.toString());
      buffer.clear();
    }

    var i = 0;
    while (i < path.length) {
      final char = path[i];
      if (char == '.') {
        flush();
        i++;
      } else if (char == '[') {
        flush();
        final close = path.indexOf(']', i);
        if (close == -1) {
          buffer.write(path.substring(i));
          break;
        }
        result.add(_bracketSegment(path.substring(i + 1, close)));
        i = close + 1;
      } else {
        buffer.write(char);
        i++;
      }
    }
    flush();
    if (result.isNotEmpty && result.first == r'$') result.removeAt(0);
    return result;
  }

  static Object _bracketSegment(String raw) {
    final inner = raw.trim();
    final quoted = inner.length >= 2 &&
        ((inner.startsWith('"') && inner.endsWith('"')) || (inner.startsWith("'") && inner.endsWith("'")));
    if (quoted) return inner.substring(1, inner.length - 1);
    return int.tryParse(inner) ?? inner;
  }
}
