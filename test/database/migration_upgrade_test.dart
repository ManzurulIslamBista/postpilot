import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';

// Old databases are built with literal SQL, so these tests do not move when the Drift definitions do.
// The SQL below is what drift generates for the tables as they stood at each schema version. Everything except
// `requests` never changed shape in v1..v3. Only the current-shape `requests` (v2, v3) is certain, because
// it is what the `from < 2` step recreates; the v1 shape is a plausible reconstruction (the app has no record of it),
// so the v1 tests prove the generic copy, not a specific historical layout.

const _now = "DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))";

const _collections =
    'CREATE TABLE "collections" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, '
    '"forked_from_id" INTEGER NULL, "created_at" INTEGER NOT NULL $_now)';
const _folders =
    'CREATE TABLE "folders" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    '"collection_id" INTEGER NOT NULL REFERENCES collections (id) ON DELETE CASCADE, '
    '"parent_folder_id" INTEGER NULL REFERENCES folders (id) ON DELETE CASCADE, "name" TEXT NOT NULL, '
    '"order_index" INTEGER NOT NULL DEFAULT 0)';
const _environments =
    'CREATE TABLE "environments" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, '
    '"is_active" INTEGER NOT NULL DEFAULT 0 CHECK ("is_active" IN (0, 1)))';
const _environmentVariables =
    'CREATE TABLE "environment_variables" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    '"environment_id" INTEGER NOT NULL REFERENCES environments (id) ON DELETE CASCADE, "key" TEXT NOT NULL, '
    '"value" TEXT NOT NULL DEFAULT \'\', "is_secret" INTEGER NOT NULL DEFAULT 0 CHECK ("is_secret" IN (0, 1)), '
    '"enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("enabled" IN (0, 1)), "order_index" INTEGER NOT NULL DEFAULT 0)';
const _history =
    'CREATE TABLE "history_entries" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "request_id" INTEGER NULL, '
    '"method" TEXT NOT NULL, "url" TEXT NOT NULL, "status_code" INTEGER NULL, "duration_ms" INTEGER NULL, '
    '"response_headers_json" TEXT NOT NULL DEFAULT \'{}\', "response_body" BLOB NULL, "sent_at" INTEGER NOT NULL $_now)';

/// `requests` as the `from < 2` step creates it (the current shape). Optional [without] leaves columns out to
/// imitate a table an older build made.
String _requestsCurrent({Set<String> without = const {}}) {
  final columns = <String, String>{
    'id': 'INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT',
    'collection_id': 'INTEGER NOT NULL REFERENCES collections (id) ON DELETE CASCADE',
    'folder_id': 'INTEGER NULL REFERENCES folders (id) ON DELETE SET NULL',
    'name': 'TEXT NOT NULL',
    'method': "TEXT NOT NULL DEFAULT 'get'",
    'url': "TEXT NOT NULL DEFAULT ''",
    'headers_json': "TEXT NOT NULL DEFAULT '[]'",
    'query_params_json': "TEXT NOT NULL DEFAULT '[]'",
    'body_type': "TEXT NOT NULL DEFAULT 'none'",
    'raw_content_type': "TEXT NOT NULL DEFAULT 'json'",
    'body_text': "TEXT NOT NULL DEFAULT ''",
    'form_fields_json': "TEXT NOT NULL DEFAULT '[]'",
    'url_encoded_fields_json': "TEXT NOT NULL DEFAULT '[]'",
    'graphql_query': "TEXT NOT NULL DEFAULT ''",
    'graphql_variables': "TEXT NOT NULL DEFAULT '{}'",
    'auth_type': "TEXT NOT NULL DEFAULT 'inherit'",
    'auth_config_json': "TEXT NOT NULL DEFAULT '{}'",
    'order_index': 'INTEGER NOT NULL DEFAULT 0',
    'updated_at': 'INTEGER NOT NULL $_now',
  };
  final definitions = [
    for (final column in columns.entries)
      if (!without.contains(column.key)) '"${column.key}" ${column.value}',
  ];
  return 'CREATE TABLE "requests" (${definitions.join(', ')})';
}

/// A plausible v1 `requests`: fewer columns, nullable `url`, and a column (`description`) the current shape no longer has.
const _requestsV1 =
    'CREATE TABLE "requests" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    '"collection_id" INTEGER NOT NULL REFERENCES collections (id) ON DELETE CASCADE, '
    '"folder_id" INTEGER NULL REFERENCES folders (id) ON DELETE SET NULL, "name" TEXT NOT NULL, '
    '"method" TEXT NOT NULL DEFAULT \'get\', "url" TEXT NULL, "headers_json" TEXT NOT NULL DEFAULT \'[]\', '
    '"query_params_json" TEXT NOT NULL DEFAULT \'[]\', "body_type" TEXT NOT NULL DEFAULT \'none\', "body_text" TEXT NULL, '
    '"description" TEXT NULL, "order_index" INTEGER NOT NULL DEFAULT 0, "updated_at" INTEGER NOT NULL $_now)';

const _v3Tables = [
  'CREATE TABLE "global_variables" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "key" TEXT NOT NULL, '
      '"value" TEXT NOT NULL DEFAULT \'\', "is_secret" INTEGER NOT NULL DEFAULT 0 CHECK ("is_secret" IN (0, 1)), '
      '"enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("enabled" IN (0, 1)))',
  'CREATE TABLE "collection_variables" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"collection_id" INTEGER NOT NULL REFERENCES collections (id) ON DELETE CASCADE, "key" TEXT NOT NULL, '
      '"value" TEXT NOT NULL DEFAULT \'\', "enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("enabled" IN (0, 1)))',
  'CREATE INDEX collection_variables_collection_id ON collection_variables (collection_id)',
  'CREATE TABLE "collection_auth" ("collection_id" INTEGER NOT NULL REFERENCES collections (id) ON DELETE CASCADE, '
      '"auth_json" TEXT NOT NULL DEFAULT \'{}\', PRIMARY KEY ("collection_id"))',
  'CREATE TABLE "request_scripts" ("request_id" INTEGER NOT NULL REFERENCES requests (id) ON DELETE CASCADE, '
      '"assertions_json" TEXT NOT NULL DEFAULT \'[]\', "extractors_json" TEXT NOT NULL DEFAULT \'[]\', '
      'PRIMARY KEY ("request_id"))',
  'CREATE TABLE "response_examples" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"request_id" INTEGER NOT NULL REFERENCES requests (id) ON DELETE CASCADE, "name" TEXT NOT NULL, '
      '"status_code" INTEGER NOT NULL, "headers_json" TEXT NOT NULL DEFAULT \'{}\', "body" TEXT NOT NULL DEFAULT \'\', '
      '"saved_at" INTEGER NOT NULL $_now)',
  'CREATE INDEX response_examples_request_id ON response_examples (request_id)',
];

const _baseRows = [
  "INSERT INTO collections (id, name) VALUES (1, 'Payments'), (2, 'Admin')",
  "INSERT INTO folders (id, collection_id, name) VALUES (1, 1, 'Users')",
  "INSERT INTO environments (id, name, is_active) VALUES (1, 'prod', 1)",
  "INSERT INTO environment_variables (environment_id, key, value) VALUES (1, 'baseUrl', 'https://api.test')",
  "INSERT INTO history_entries (request_id, method, url, status_code) VALUES (5, 'GET', 'https://api.test/users', 200)",
];

const _v4Only = [
  'entity_uids',
  'git_links',
  'git_base_entries',
  'setting_entries',
  'request_setting_entries',
  'entity_docs',
  'entity_tags',
];

/// A database that SQLite believes is at [version]: [statements] run in the connection's `setup`, which is
/// before drift reads `user_version`, so drift sees an old file and runs its real `onUpgrade`.
/// [handle] receives the raw connection so a test can look at the file after a migration failed.
AppDatabase _openAt(int version, List<String> statements, {void Function(dynamic raw)? handle}) {
  return AppDatabase.forTesting(
    NativeDatabase.memory(
      setup: (raw) {
        // Some SQLite builds ship with foreign keys on by default; the migration has to cope with that.
        raw.execute('PRAGMA foreign_keys = ON');
        for (final statement in statements) {
          raw.execute(statement);
        }
        raw.execute('PRAGMA user_version = $version');
        handle?.call(raw);
      },
    ),
  );
}

Future<Set<String>> _objectNames(AppDatabase db) async {
  final rows = await db.customSelect("SELECT name FROM sqlite_master WHERE type IN ('table', 'index')").get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<int> _scalar(AppDatabase db, String sql) async =>
    (await db.customSelect(sql).getSingle()).data.values.single as int;

DateTime _at(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

void main() {
  group('schema v1 -> current', () {
    late AppDatabase db;

    setUp(() {
      db = _openAt(1, [
        _collections,
        _folders,
        _requestsV1,
        _environments,
        _environmentVariables,
        _history,
        ..._baseRows,
        // Non-contiguous ids on purpose: the ids must survive, not be renumbered.
        'INSERT INTO requests (id, collection_id, folder_id, name, method, url, headers_json, query_params_json, '
            'body_type, body_text, description, order_index, updated_at) VALUES '
            '(5, 1, NULL, \'List users\', \'get\', \'https://api.test/users\', '
            '\'[{"key":"Accept","value":"application/json"}]\', \'[{"key":"page","value":"1"}]\', '
            '\'none\', NULL, \'old note\', 0, 1700000000), '
            '(9, 1, 1, \'Create user\', \'post\', NULL, \'[]\', \'[]\', \'raw\', \'{"name":"x"}\', NULL, 1, 1700000100), '
            '(12, 2, NULL, \'Ping\', \'head\', \'https://admin.test/ping\', \'[]\', \'[]\', \'none\', NULL, NULL, 0, 1700000200)',
      ]);
    });
    tearDown(() => db.close());

    test('keeps every saved request, with its id, and fills new columns with their defaults', () async {
      final rows = await (db.select(db.requests)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

      expect(rows.map((r) => r.id), [5, 9, 12]);
      expect(rows.map((r) => r.name), ['List users', 'Create user', 'Ping']);
      expect(rows.map((r) => r.collectionId), [1, 1, 2]);
      expect(rows.map((r) => r.folderId), [null, 1, null]);
      expect(rows.map((r) => r.method), ['get', 'post', 'head']);
      // A NULL url in the old table becomes the new column's default instead of failing the whole upgrade.
      expect(rows.map((r) => r.url), ['https://api.test/users', '', 'https://admin.test/ping']);
      expect(rows[0].headersJson, '[{"key":"Accept","value":"application/json"}]');
      expect(rows[0].queryParamsJson, '[{"key":"page","value":"1"}]');
      expect(rows[1].bodyType, 'raw');
      expect(rows[1].bodyText, '{"name":"x"}');
      expect(rows[0].bodyText, '', reason: 'NULL body_text falls back to the default');
      expect(rows.map((r) => r.orderIndex), [0, 1, 0]);
      expect(rows[0].updatedAt.isAtSameMomentAs(_at(1700000000)), isTrue);
      expect(rows[2].updatedAt.isAtSameMomentAs(_at(1700000200)), isTrue);

      // Columns the old table never had take their defaults.
      for (final row in rows) {
        expect(row.rawContentType, 'json');
        expect(row.formFieldsJson, '[]');
        expect(row.urlEncodedFieldsJson, '[]');
        expect(row.graphqlQuery, '');
        expect(row.graphqlVariables, '{}');
        expect(row.authType, 'inherit');
        expect(row.authConfigJson, '{}');
      }
    });

    test('leaves no scratch table behind, creates every later table and stamps the current version', () async {
      final names = await _objectNames(db);
      expect(names.where((n) => n.startsWith('requests_legacy')), isEmpty);
      expect(names, containsAll([..._v4Only, 'global_variables', 'request_scripts', 'response_examples']));
      expect(names, containsAll(['collection_variables_collection_id', 'response_examples_request_id', 'entity_uids_uid']));
      expect(await _scalar(db, 'PRAGMA user_version'), db.schemaVersion);
      // The old column that no longer exists is gone from the new table.
      final columns = (await db.customSelect('PRAGMA table_info("requests")').get()).map((r) => r.read<String>('name'));
      expect(columns, isNot(contains('description')));
    });

    test('rows the migration did not touch survive', () async {
      expect((await db.collectionsDao.watchAllCollections().first).map((c) => c.name), unorderedEquals(['Payments', 'Admin']));
      expect(await _scalar(db, 'SELECT COUNT(*) FROM folders'), 1);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM environments'), 1);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM environment_variables'), 1);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM history_entries'), 1);
    });

    test('foreign keys and cascades work on the rebuilt table', () async {
      expect(await _scalar(db, 'PRAGMA foreign_keys'), 1);
      // A child table created after the rebuild points at the new table and cascades from it.
      await db.requestScriptsDao.upsert(RequestScriptsCompanion.insert(requestId: Value(9)));
      await db.responseExamplesDao.add(ResponseExamplesCompanion.insert(requestId: 9, name: 'ok', statusCode: 200));

      // A raw folder delete (not the DAO, which removes the folder's requests itself) must null the
      // request's folder via ON DELETE SET NULL.
      await db.customStatement('DELETE FROM folders WHERE id = 1');
      expect((await (db.select(db.requests)..where((t) => t.id.equals(9))).getSingle()).folderId, isNull);

      await db.requestsDao.deleteRequest(9);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM request_scripts'), 0);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM response_examples'), 0);

      // ON DELETE CASCADE from the collection.
      await db.collectionsDao.deleteCollection(1);
      expect((await db.select(db.requests).get()).map((r) => r.id), [12]);
    });

    test('new requests get an id above the migrated ones', () async {
      final id = await db.requestsDao.createRequest(RequestsCompanion.insert(collectionId: 1, name: 'new'));
      expect(id, greaterThan(12));
    });
  });

  test('a v1 table that shares only a few columns with the current one still keeps all rows', () async {
    final db = _openAt(1, [
      _collections,
      _folders,
      'CREATE TABLE "requests" ("id" INTEGER PRIMARY KEY, "collection_id" INTEGER NOT NULL, "name" TEXT, "url" TEXT)',
      _environments,
      _environmentVariables,
      _history,
      "INSERT INTO collections (id, name) VALUES (1, 'c')",
      "INSERT INTO requests (id, collection_id, name, url) VALUES (3, 1, 'a', 'https://a.test'), (4, 1, NULL, NULL)",
    ]);
    addTearDown(db.close);

    final rows = await (db.select(db.requests)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    expect(rows.map((r) => r.id), [3, 4]);
    expect(rows.map((r) => r.name), ['a', ''], reason: 'a NULL name in an old row becomes empty, not a failed upgrade');
    expect(rows.map((r) => r.url), ['https://a.test', '']);
    expect(rows.map((r) => r.method), ['get', 'get']);
  });

  test('a large v1 table is copied completely', () async {
    final inserts = [
      for (var start = 1; start <= 1200; start += 300)
        'INSERT INTO requests (id, collection_id, name, url, headers_json, query_params_json, body_type, order_index, updated_at) VALUES ${[
          for (var i = start; i < start + 300; i++) "($i, 1, 'r$i', 'https://x.test/$i', '[]', '[]', 'none', $i, 1700000000)",
        ].join(', ')}',
    ];
    final db = _openAt(1, [_collections, _folders, _requestsV1, _environments, _environmentVariables, _history, _baseRows.first, ...inserts]);
    addTearDown(db.close);

    expect(await _scalar(db, 'SELECT COUNT(*) FROM requests'), 1200);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM requests WHERE url = \'https://x.test/\' || id AND name = \'r\' || id'), 1200);
    expect(await _scalar(db, 'SELECT SUM(order_index) FROM requests'), 1200 * 1201 ~/ 2);
  });

  group('schema v2 -> current', () {
    test('keeps its requests untouched, without a needless rebuild, and adds the v3 and v4 tables', () async {
      final db = _openAt(2, [
        _collections,
        _folders,
        _requestsCurrent(),
        // An index dies with a dropped table, so its survival proves the table was not rebuilt.
        'CREATE INDEX requests_marker ON requests (name)',
        _environments,
        _environmentVariables,
        _history,
        ..._baseRows,
        'INSERT INTO requests (id, collection_id, name, url, auth_type, graphql_query, body_text) VALUES '
            '(1, 1, \'Login\', \'https://api.test/login\', \'bearer\', \'{ me { id } }\', \'{"u":1}\'), '
            '(2, 2, \'Logout\', \'https://api.test/logout\', \'inherit\', \'\', \'\')',
      ]);
      addTearDown(db.close);

      final rows = await (db.select(db.requests)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      expect(rows.map((r) => r.name), ['Login', 'Logout']);
      expect(rows[0].authType, 'bearer');
      expect(rows[0].graphqlQuery, '{ me { id } }');
      expect(rows[0].bodyText, '{"u":1}');

      final names = await _objectNames(db);
      expect(names, contains('requests_marker'));
      expect(names, containsAll([..._v4Only, 'global_variables', 'collection_variables', 'collection_auth', 'request_scripts']));
      expect(await _scalar(db, 'PRAGMA user_version'), db.schemaVersion);
    });
  });

  group('schema v3 -> current', () {
    AppDatabase openV3({Set<String> withoutColumns = const {}}) => _openAt(3, [
      _collections,
      _folders,
      _requestsCurrent(without: withoutColumns),
      _environments,
      _environmentVariables,
      _history,
      ..._v3Tables,
      ..._baseRows,
      "INSERT INTO requests (id, collection_id, name, url) VALUES (1, 1, 'Login', 'https://api.test/login'), (2, 1, 'Me', 'https://api.test/me')",
      "INSERT INTO request_scripts (request_id, assertions_json) VALUES (1, '[{\"type\":\"statusEquals\"}]')",
      "INSERT INTO response_examples (request_id, name, status_code, body) VALUES (2, 'ok', 200, '{}')",
      "INSERT INTO global_variables (key, value) VALUES ('token', 't')",
      "INSERT INTO collection_variables (collection_id, key, value) VALUES (1, 'v', '1')",
      "INSERT INTO collection_auth (collection_id, auth_json) VALUES (1, '{\"type\":\"bearer\"}')",
    ]);

    test('creates the v4 tables and keeps every existing row, including rows of tables that point at requests', () async {
      final db = openV3();
      addTearDown(db.close);

      expect(await _objectNames(db), containsAll([..._v4Only, 'entity_uids_uid', 'entity_tags_tag']));
      expect((await db.select(db.requests).get()).map((r) => r.name), ['Login', 'Me']);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM request_scripts'), 1);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM response_examples'), 1);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM global_variables'), 1);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM collection_variables'), 1);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM collection_auth'), 1);

      await db.requestsDao.deleteRequest(2);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM response_examples'), 0, reason: 'cascade still works');
    });

    test('a v3 requests table missing newer columns is rebuilt without losing its rows or its children', () async {
      final db = openV3(withoutColumns: {'url_encoded_fields_json', 'graphql_variables', 'auth_config_json'});
      addTearDown(db.close);

      final rows = await (db.select(db.requests)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      expect(rows.map((r) => r.name), ['Login', 'Me']);
      expect(rows.map((r) => r.url), ['https://api.test/login', 'https://api.test/me']);
      expect(rows.map((r) => r.graphqlVariables), ['{}', '{}']);
      expect(rows.map((r) => r.authConfigJson), ['{}', '{}']);
      // The tables that reference requests must not have cascaded away while the old table was dropped.
      expect(await _scalar(db, 'SELECT COUNT(*) FROM request_scripts'), 1);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM response_examples'), 1);
      expect(await _scalar(db, 'PRAGMA foreign_keys'), 1);

      await db.requestsDao.deleteRequest(1);
      expect(await _scalar(db, 'SELECT COUNT(*) FROM request_scripts'), 0, reason: 'the rebuilt table is still the cascade parent');
    });
  });

  test('a failed copy rolls back and leaves the original table and its rows alone', () async {
    dynamic raw;
    final db = _openAt(
      1,
      [
        _collections,
        _folders,
        // collection_id is nullable here, so the row below cannot be placed in the new NOT NULL column.
        'CREATE TABLE "requests" ("id" INTEGER PRIMARY KEY, "collection_id" INTEGER, "name" TEXT NOT NULL)',
        _environments,
        _environmentVariables,
        _history,
        "INSERT INTO collections (id, name) VALUES (1, 'c')",
        "INSERT INTO requests (id, collection_id, name) VALUES (1, 1, 'fine'), (2, NULL, 'orphan')",
      ],
      handle: (r) => raw = r,
    );

    await expectLater(db.select(db.requests).get(), throwsA(anything));

    // Back to the old file: both rows, no scratch table, and the version was not advanced.
    expect(raw.select('SELECT COUNT(*) AS n FROM requests').first['n'], 2);
    expect(raw.select("SELECT name FROM sqlite_master WHERE name LIKE 'requests_legacy%'"), isEmpty);
    expect(raw.select('PRAGMA user_version').first['user_version'], 1);
    try {
      await db.close();
    } catch (_) {}
  });

  test('migrations never use Migrator.addColumn, which crashes the drift web worker', () {
    final files = [
      File('lib/core/database/app_database.dart'),
      ...Directory('lib/core/database/migrations').listSync().whereType<File>(),
    ];
    for (final file in files) {
      final code = file.readAsLinesSync().where((line) => !line.trimLeft().startsWith('//')).join('\n');
      expect(code, isNot(contains('addColumn')), reason: file.path);
      expect(code, isNot(contains('ALTER TABLE')), reason: file.path);
    }
  });
}
