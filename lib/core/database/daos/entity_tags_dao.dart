import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/entity_tags_table.dart';

part 'entity_tags_dao.g.dart';

/// Tags are case-insensitive identities that keep the spelling they were
/// first given; every read returns them sorted case-insensitively.
@DriftAccessor(tables: [EntityTags])
class EntityTagsDao extends DatabaseAccessor<AppDatabase> with _$EntityTagsDaoMixin {
  EntityTagsDao(super.db);

  SimpleSelectStatement<$EntityTagsTable, EntityTag> _rowsOf(String kind, int id) =>
      select(entityTags)..where((t) => t.kind.equals(kind) & t.localId.equals(id));

  Future<List<String>> tagsOf(String kind, int id) async => _sorted((await _rowsOf(kind, id).get()).map((r) => r.tag));

  Stream<List<String>> watchTags(String kind, int id) => _rowsOf(kind, id).watch().map((rows) => _sorted(rows.map((r) => r.tag)));

  /// Replaces the entity's tags: trimmed, empties dropped, duplicates (ignoring
  /// case) collapsed to their first spelling.
  Future<void> setTags(String kind, int id, List<String> tags) => transaction(() async {
        await (delete(entityTags)..where((t) => t.kind.equals(kind) & t.localId.equals(id))).go();
        final clean = _normalise(tags);
        if (clean.isEmpty) return;
        await batch(
          (b) => b.insertAll(entityTags, [for (final tag in clean) EntityTagsCompanion.insert(kind: kind, localId: id, tag: tag)]),
        );
      });

  /// Every tag in use, one spelling per tag (ignoring case), sorted.
  Stream<List<String>> watchAllTags() => (selectOnly(entityTags, distinct: true)..addColumns([entityTags.tag]))
      .map((row) => row.read(entityTags.tag)!)
      .watch()
      .map((tags) {
    final seen = <String>{};
    return [
      for (final tag in _sorted(tags))
        if (seen.add(tag.toLowerCase())) tag,
    ];
  });

  /// Local ids of the [kind] entities carrying [tag] (ignoring case).
  Future<Set<int>> localIdsWithTag(String kind, String tag) async {
    final wanted = tag.trim().toLowerCase();
    final rows = await (select(entityTags)..where((t) => t.kind.equals(kind))).get();
    return {
      for (final r in rows)
        if (r.tag.toLowerCase() == wanted) r.localId,
    };
  }

  Future<Map<int, List<String>>> tagsByLocalId(String kind) async {
    final rows = await (select(entityTags)..where((t) => t.kind.equals(kind))).get();
    final byId = <int, List<String>>{};
    for (final r in rows) {
      (byId[r.localId] ??= []).add(r.tag);
    }
    return {for (final e in byId.entries) e.key: _sorted(e.value)};
  }

  static List<String> _normalise(Iterable<String> tags) {
    final seen = <String>{};
    return [
      for (final raw in tags)
        if (raw.trim().isNotEmpty && seen.add(raw.trim().toLowerCase())) raw.trim(),
    ];
  }

  static List<String> _sorted(Iterable<String> tags) => tags.toList()
    ..sort((a, b) {
      final byLower = a.toLowerCase().compareTo(b.toLowerCase());
      return byLower != 0 ? byLower : a.compareTo(b);
    });
}
