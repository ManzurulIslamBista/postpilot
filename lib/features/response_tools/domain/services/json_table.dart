import 'dart:convert';

/// A JSON array of objects laid out as rows and columns.
final class JsonTable {
  /// Where the array sits in the document (`''` = the root).
  final String path;
  final List<String> columns;
  final List<Map<String, Object?>> rows;

  const JsonTable({required this.path, required this.columns, required this.rows});

  static String cell(Object? value) => switch (value) {
        null => '',
        String s => s,
        num _ || bool _ => '$value',
        _ => jsonEncode(value),
      };

  /// RFC 4180 CSV: fields with commas, quotes or newlines are quoted.
  String toCsv() {
    String field(String s) => s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
    final b = StringBuffer()..writeln(columns.map(field).join(','));
    for (final row in rows) {
      b.writeln(columns.map((c) => field(cell(row[c]))).join(','));
    }
    return b.toString();
  }

  /// The first array of objects in [json]: the root, or the first one found
  /// within three levels (`data.items`, `result`, `records`). `null` if none.
  static JsonTable? find(Object? json, {int maxRows = 1000}) {
    final hit = _search(json, '', 0);
    if (hit == null) return null;
    final list = hit.$2;
    final rows = [for (final e in list.take(maxRows)) Map<String, Object?>.from(e as Map)];
    final columns = <String>[];
    final seen = <String>{};
    for (final row in rows.take(100)) {
      for (final key in row.keys) {
        if (seen.add(key)) columns.add(key);
      }
    }
    return JsonTable(path: hit.$1, columns: columns, rows: rows);
  }

  static (String, List<dynamic>)? _search(Object? node, String path, int depth) {
    if (node is List) {
      if (node.isNotEmpty && node.every((e) => e is Map)) return (path, node);
      return null;
    }
    if (node is Map && depth < 3) {
      for (final e in node.entries) {
        final found = _search(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}', depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }
}
