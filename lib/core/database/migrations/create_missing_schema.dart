import 'package:drift/drift.dart';

import 'rebuild_table_keeping_rows.dart';

/// Whether [db] already holds tables of the app, i.e. a database that is "new" only because its version number was lost.
Future<bool> hasAppTables(GeneratedDatabase db) async {
  final tables = db.allTables.map((t) => t.actualTableName).toSet();
  final rows = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get();
  return rows.any((row) => tables.contains(row.read<String>('name')));
}

/// Creates every table and index of [db] that is not there yet, and leaves what is there (with its rows) alone, so it
/// can run on a database that `createAll` would fail on ("index ... already exists"). A table an older build made, which
/// lacks a column of today's definition, is rebuilt with its rows (a lost version number says nothing about the shape).
Future<void> createMissingSchema(GeneratedDatabase db, Migrator m) async {
  final entities = db.allSchemaEntities.toList();
  // Tables first: rebuilding one drops its indexes, which the second pass puts back.
  for (final entity in entities.whereType<TableInfo<Table, dynamic>>()) {
    if (await tableLacksColumns(db, entity)) {
      await rebuildTableKeepingRows(db, m, entity);
    } else {
      // `CREATE TABLE IF NOT EXISTS`
      await m.createTable(entity);
    }
  }
  for (final entity in entities) {
    switch (entity) {
      case TableInfo():
        break;
      case Index():
        final statements = entity.createStatementsByDialect;
        await db.customStatement(_idempotent(statements[SqlDialect.sqlite] ?? statements.values.first));
      default:
        await m.create(entity);
    }
  }
}

String _idempotent(String createIndex) => createIndex.replaceFirstMapped(
      RegExp(r'^CREATE (UNIQUE )?INDEX (?!IF NOT EXISTS)', caseSensitive: false),
      (match) => 'CREATE ${match[1] ?? ''}INDEX IF NOT EXISTS ',
    );
