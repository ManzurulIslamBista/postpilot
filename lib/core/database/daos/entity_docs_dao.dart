import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/entity_docs_table.dart';

part 'entity_docs_dao.g.dart';

@DriftAccessor(tables: [EntityDocs])
class EntityDocsDao extends DatabaseAccessor<AppDatabase> with _$EntityDocsDaoMixin {
  EntityDocsDao(super.db);

  SimpleSelectStatement<$EntityDocsTable, EntityDoc> _rowOf(String kind, int id) =>
      select(entityDocs)..where((t) => t.kind.equals(kind) & t.localId.equals(id));

  Future<String> markdownOf(String kind, int id) async => (await _rowOf(kind, id).getSingleOrNull())?.markdown ?? '';

  Stream<String> watchMarkdown(String kind, int id) =>
      _rowOf(kind, id).watchSingleOrNull().map((r) => r?.markdown ?? '');

  /// Empty [text] removes the row instead of storing an empty document.
  Future<void> setMarkdown(String kind, int id, String text) {
    if (text.isEmpty) {
      return (delete(entityDocs)..where((t) => t.kind.equals(kind) & t.localId.equals(id))).go();
    }
    return into(entityDocs).insertOnConflictUpdate(
      EntityDocsCompanion.insert(kind: kind, localId: id, markdown: Value(text)),
    );
  }

  Future<Map<int, String>> markdownByLocalId(String kind) async {
    final rows = await (select(entityDocs)..where((t) => t.kind.equals(kind))).get();
    return {for (final r in rows) r.localId: r.markdown};
  }
}
