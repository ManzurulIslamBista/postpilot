import 'package:drift/drift.dart';

@TableIndex(name: 'entity_tags_tag', columns: {#tag})
class EntityTags extends Table {
  TextColumn get kind => text()();
  IntColumn get localId => integer()();
  TextColumn get tag => text()();

  @override
  Set<Column> get primaryKey => {kind, localId, tag};
}
