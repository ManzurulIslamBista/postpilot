import 'package:drift/drift.dart';

/// Whether the live table behind [table] lacks a column its current Drift
/// definition has, i.e. it was created by an older build of the app.
Future<bool> tableLacksColumns(GeneratedDatabase db, TableInfo<Table, dynamic> table) async {
  if (!await _tableExists(db, table.actualTableName)) return false;
  final live = (await _columnsOf(db, table.actualTableName)).map((c) => c.name).toSet();
  return table.$columns.any((column) => !live.contains(column.name));
}

/// Recreates [table] in the shape the current Drift definition describes and
/// carries every row of the old table over, instead of `deleteTable` +
/// `createTable`, which throws away whatever the user had saved.
///
/// Columns present in both shapes are copied (a NULL in a column the new shape
/// declares NOT NULL falls back to that column's default); columns only the new
/// shape has take their default. It deliberately avoids `ALTER TABLE`:
/// `Migrator.addColumn` crashes the drift web worker on this project, and only
/// `createTable` / `deleteTable` are proven there. The old rows are parked in a
/// scratch table made with `CREATE TABLE ... AS SELECT`, the scratch table is
/// dropped only once the new table holds the same number of rows, and the whole
/// swap runs in one transaction, so a failure rolls back to the untouched
/// original instead of leaving a half-built table behind.
///
/// Returns the number of rows kept. Throws, with the original table intact, if
/// the copy did not keep every row.
Future<int> rebuildTableKeepingRows(GeneratedDatabase db, Migrator m, TableInfo<Table, dynamic> table) async {
  final name = table.actualTableName;
  if (!await _tableExists(db, name)) {
    await m.createTable(table);
    return 0;
  }

  // The pragma is a no-op inside a transaction, so it is switched before one starts. With it on, dropping
  // the old table would cascade into every child row that points at it.
  final foreignKeys = (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>('foreign_keys');
  if (foreignKeys != 0) await db.customStatement('PRAGMA foreign_keys = OFF');
  try {
    return await db.transaction(() async {
      final scratch = await _unusedName(db, '${name}_legacy');
      await db.customStatement('CREATE TABLE ${_q(scratch)} AS SELECT * FROM ${_q(name)}');
      final expected = await _countRows(db, scratch);

      await m.deleteTable(name);
      await m.createTable(table);

      final oldColumns = (await _columnsOf(db, scratch)).map((c) => c.name).toSet();
      final shared = [
        for (final column in await _columnsOf(db, name))
          if (oldColumns.contains(column.name)) column,
      ];
      if (expected > 0 && shared.isEmpty) {
        throw StateError('Cannot keep the rows of "$name": the old table shares no column with the new one.');
      }
      if (shared.isNotEmpty) {
        final targets = shared.map((c) => _q(c.name)).join(', ');
        final sources = shared.map(_sourceExpression).join(', ');
        await db.customStatement('INSERT INTO ${_q(name)} ($targets) SELECT $sources FROM ${_q(scratch)}');
      }

      final kept = await _countRows(db, name);
      if (kept != expected) {
        throw StateError('Rebuilding "$name" kept $kept of $expected rows; the upgrade was rolled back.');
      }
      await db.customStatement('DROP TABLE ${_q(scratch)}');
      return kept;
    });
  } finally {
    if (foreignKeys != 0) await db.customStatement('PRAGMA foreign_keys = ON');
  }
}

/// The SELECT expression that feeds [column] of the new table from the old one.
String _sourceExpression(_Column column) {
  final source = _q(column.name);
  if (!column.notNull || column.isPrimaryKey) return source;
  final fallback = column.defaultValue;
  if (fallback != null) return 'COALESCE($source, $fallback)';
  // A NOT NULL text column with no default (`name`) must still accept a row an older build left NULL.
  if (column.type.toUpperCase().contains('TEXT')) return "COALESCE($source, '')";
  return source;
}

String _q(String identifier) => '"${identifier.replaceAll('"', '""')}"';

Future<bool> _tableExists(GeneratedDatabase db, String name) async {
  final rows = await db
      .customSelect(
        "SELECT 1 AS present FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable<String>(name)],
      )
      .get();
  return rows.isNotEmpty;
}

Future<String> _unusedName(GeneratedDatabase db, String wanted) async {
  var candidate = wanted;
  for (var n = 2; await _tableExists(db, candidate); n++) {
    candidate = '${wanted}_$n';
  }
  return candidate;
}

Future<int> _countRows(GeneratedDatabase db, String table) async {
  final row = await db.customSelect('SELECT COUNT(*) AS n FROM ${_q(table)}').getSingle();
  return row.read<int>('n');
}

Future<List<_Column>> _columnsOf(GeneratedDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info(${_q(table)})').get();
  return [
    for (final row in rows)
      _Column(
        name: row.read<String>('name'),
        type: row.read<String>('type'),
        notNull: row.read<int>('notnull') != 0,
        defaultValue: row.readNullable<String>('dflt_value'),
        isPrimaryKey: row.read<int>('pk') != 0,
      ),
  ];
}

class _Column {
  final String name;
  final String type;
  final bool notNull;
  final String? defaultValue;
  final bool isPrimaryKey;

  const _Column({
    required this.name,
    required this.type,
    required this.notNull,
    required this.defaultValue,
    required this.isPrimaryKey,
  });
}
