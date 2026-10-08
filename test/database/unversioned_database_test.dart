import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';

// The browser's IndexedDB file system did not save the version number a first start wrote, unless something was written
// afterwards: a visit without a write left a database with all its tables and "user_version = 0", and every later start
// ran createAll again and failed on "index ... already exists". These tests rebuild exactly that file on disk.

AppDatabase _open(File file) => AppDatabase.forTesting(NativeDatabase(file));

/// Opens [file] as a browser would find it after its version number was lost: `setup` runs before drift reads it.
AppDatabase _openUnversioned(File file) =>
    AppDatabase.forTesting(NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA user_version = 0')));

Future<int> _scalar(AppDatabase db, String sql) async =>
    (await db.customSelect(sql).getSingle()).data.values.single as int;

Future<Set<String>> _objects(AppDatabase db) async {
  final rows = await db.customSelect("SELECT name FROM sqlite_master WHERE type IN ('table', 'index')").get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('postpilot_unversioned_');
    file = File('${dir.path}${Platform.pathSeparator}app.sqlite');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // Windows may still hold the file for a moment; the temp directory is cleaned up by the OS.
    }
  });

  /// A file with everything created and some rows, as an earlier start left it.
  Future<void> createWithRows({List<String> extra = const []}) async {
    final db = _open(file);
    await db.customStatement("INSERT INTO collections (name) VALUES ('kept')");
    for (final statement in extra) {
      await db.customStatement(statement);
    }
    await db.close();
  }

  test('a new database has its version number written during the open', () async {
    final db = _open(file);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM collections'), 0);
    await db.close();

    final reopened = _open(file);
    addTearDown(reopened.close);
    expect(await _scalar(reopened, 'PRAGMA user_version'), 6);
  });

  test('a database with all its tables but no version opens, keeps its rows and gets its version', () async {
    await createWithRows();

    final db = _openUnversioned(file);
    addTearDown(db.close);
    expect(await _scalar(db, "SELECT COUNT(*) FROM collections WHERE name = 'kept'"), 1);
    expect(await _scalar(db, 'PRAGMA user_version'), db.schemaVersion);
  });

  test('a table an older build made, with a column missing, is rebuilt with its rows and the indexes come back', () async {
    await createWithRows(extra: [
      "INSERT INTO requests (collection_id, name) VALUES (1, 'old request')",
      'ALTER TABLE requests DROP COLUMN graphql_variables',
      'DROP INDEX collection_variables_collection_id',
    ]);

    final db = _openUnversioned(file);
    addTearDown(db.close);
    expect(await _scalar(db, "SELECT COUNT(*) FROM requests WHERE name = 'old request'"), 1);
    final variables = await db.customSelect('SELECT graphql_variables FROM requests').getSingle();
    expect(variables.read<String>('graphql_variables'), '{}', reason: 'the column is back, with its default');
    expect(await _objects(db), contains('collection_variables_collection_id'));
    expect(await _scalar(db, 'PRAGMA user_version'), db.schemaVersion);
  });

  test('what an unversioned database lacks is created, and nothing that is there is touched', () async {
    await createWithRows(extra: ['DROP INDEX entity_tags_tag', 'DROP TABLE entity_tags']);

    final db = _openUnversioned(file);
    addTearDown(db.close);
    final names = await _objects(db);
    expect(names, containsAll(['entity_tags', 'entity_tags_tag', 'collection_variables_collection_id', 'entity_uids_uid']));
    expect(await _scalar(db, "SELECT COUNT(*) FROM collections WHERE name = 'kept'"), 1);
    expect(await _scalar(db, 'PRAGMA user_version'), db.schemaVersion);
  });
}
