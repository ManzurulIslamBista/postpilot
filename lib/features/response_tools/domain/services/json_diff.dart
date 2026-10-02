import 'json_tree.dart';

enum JsonChangeKind { added, removed, changed }

final class JsonChange {
  final JsonChangeKind kind;
  final String path;
  final Object? before;
  final Object? after;

  const JsonChange(this.kind, this.path, {this.before, this.after});
}

final class JsonDiffResult {
  final List<JsonChange> changes;

  /// Everything the walk compared, so "3 of 120 values differ" can be shown.
  final int compared;

  const JsonDiffResult(this.changes, this.compared);

  bool get isIdentical => changes.isEmpty;
  int count(JsonChangeKind kind) => changes.where((c) => c.kind == kind).length;
}

/// Structural comparison of two JSON documents: keys are matched by name and
/// list items by position, and each difference is reported with the path that
/// `JsonPathResolver` understands. Far more useful than a text diff, which
/// reports every re-ordered key and re-indented line.
abstract final class JsonDiff {
  /// Differences at keys named in [ignoreKeys] (`updated_at`, `requestId`...)
  /// are dropped: they differ on every call and hide the real change.
  static JsonDiffResult compare(Object? before, Object? after, {Set<String> ignoreKeys = const {}, int limit = 500}) {
    final changes = <JsonChange>[];
    var compared = 0;
    final ignored = ignoreKeys.map((k) => k.toLowerCase()).toSet();

    void walk(Object? a, Object? b, String path) {
      if (changes.length >= limit) return;
      compared++;
      if (a is Map && b is Map) {
        for (final key in a.keys) {
          if (ignored.contains('$key'.toLowerCase())) continue;
          final child = JsonPaths.key(path, '$key');
          if (!b.containsKey(key)) {
            changes.add(JsonChange(JsonChangeKind.removed, child, before: a[key]));
          } else {
            walk(a[key], b[key], child);
          }
        }
        for (final key in b.keys) {
          if (ignored.contains('$key'.toLowerCase()) || a.containsKey(key)) continue;
          changes.add(JsonChange(JsonChangeKind.added, JsonPaths.key(path, '$key'), after: b[key]));
        }
      } else if (a is List && b is List) {
        final shared = a.length < b.length ? a.length : b.length;
        for (var i = 0; i < shared; i++) {
          walk(a[i], b[i], JsonPaths.index(path, i));
        }
        for (var i = shared; i < a.length; i++) {
          changes.add(JsonChange(JsonChangeKind.removed, JsonPaths.index(path, i), before: a[i]));
        }
        for (var i = shared; i < b.length; i++) {
          changes.add(JsonChange(JsonChangeKind.added, JsonPaths.index(path, i), after: b[i]));
        }
      } else if (a != b) {
        changes.add(JsonChange(JsonChangeKind.changed, path.isEmpty ? r'$' : path, before: a, after: b));
      }
    }

    walk(before, after, '');
    return JsonDiffResult(changes, compared);
  }
}
