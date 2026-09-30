import 'dart:async';
import 'package:drift/drift.dart' show TableInfo, TableUpdateQuery;
import '../../../../core/database/daos/entity_tags_dao.dart';
import '../../domain/entities/entity_kind.dart';
import '../../domain/repositories/tag_repository.dart';
import '../../domain/services/tag_normalizer.dart';

final class TagRepositoryImpl implements TagRepository {
  final EntityTagsDao _dao;
  const TagRepositoryImpl(this._dao);

  @override
  Stream<List<String>> watchTags(EntityKind kind, int id) => _dao.watchTags(kind.dbValue, id);

  @override
  Future<void> setTags(EntityKind kind, int id, List<String> tags) => _dao.setTags(kind.dbValue, id, tags);

  /// Tag rows outlive the collection, folder or request they were put on (they
  /// have no foreign key), so only tags of entities that still exist count:
  /// otherwise a deleted request would leave its tag in the filter for good.
  @override
  Stream<List<String>> watchAllTags() {
    final db = _dao.attachedDatabase;
    String exists(EntityKind kind, TableInfo table) =>
        "(t.kind = '${kind.dbValue}' AND EXISTS (SELECT 1 FROM ${table.actualTableName} e WHERE e.id = t.local_id))";

    return _dao
        .customSelect(
          'SELECT DISTINCT t.tag AS tag FROM ${db.entityTags.actualTableName} t WHERE '
          '${exists(EntityKind.collection, db.collections)} OR '
          '${exists(EntityKind.folder, db.folders)} OR '
          '${exists(EntityKind.request, db.requests)}',
          readsFrom: {db.entityTags, db.collections, db.folders, db.requests},
        )
        .watch()
        .map((rows) => TagNormalizer.normalise([for (final row in rows) row.read<String>('tag')]..sort()))
        .distinct(_sameTags);
  }

  /// The query re-runs whenever a request is saved, so repeats are dropped here.
  static bool _sameTags(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Future<Map<int, List<String>>> tagsByLocalId(EntityKind kind) => _dao.tagsByLocalId(kind.dbValue);

  @override
  Stream<Map<int, List<String>>> watchTagsByLocalId(EntityKind kind) {
    final updates = _dao.tableUpdates(TableUpdateQuery.onTable(_dao.entityTags));
    late final StreamController<Map<int, List<String>>> controller;
    StreamSubscription<Object?>? subscription;

    Future<void> emit() async {
      try {
        final tags = await _dao.tagsByLocalId(kind.dbValue);
        if (!controller.isClosed) controller.add(tags);
      } catch (error, stack) {
        if (!controller.isClosed) controller.addError(error, stack);
      }
    }

    controller = StreamController(
      onListen: () {
        subscription = updates.listen((_) => emit());
        emit();
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}
