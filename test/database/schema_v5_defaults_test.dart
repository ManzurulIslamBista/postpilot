import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/database/app_database.dart';
import 'package:postpilot/features/defaults/data/defaults_repository_impl.dart';
import 'package:postpilot/features/defaults/domain/entities/default_variable.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';

// A v4 database is built with literal SQL, so this test does not move when the Drift definitions do: the SQL is
// what drift generated for the tables as they stood at schema version 4. Opening it must run the real `onUpgrade`,
// which has to add the three tables of version 5 (`folder_defaults`, `collection_defaults`, `history_payloads`)
// without touching a single existing row.

const _now = "DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))";

const _v4 = [
  'CREATE TABLE "collections" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, '
      '"forked_from_id" INTEGER NULL, "created_at" INTEGER NOT NULL $_now)',
  'CREATE TABLE "folders" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"collection_id" INTEGER NOT NULL REFERENCES collections (id) ON DELETE CASCADE, '
      '"parent_folder_id" INTEGER NULL REFERENCES folders (id) ON DELETE CASCADE, "name" TEXT NOT NULL, '
      '"order_index" INTEGER NOT NULL DEFAULT 0)',
  'CREATE TABLE "requests" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"collection_id" INTEGER NOT NULL REFERENCES collections (id) ON DELETE CASCADE, '
      '"folder_id" INTEGER NULL REFERENCES folders (id) ON DELETE SET NULL, "name" TEXT NOT NULL, '
      "\"method\" TEXT NOT NULL DEFAULT 'get', \"url\" TEXT NOT NULL DEFAULT '', "
      "\"headers_json\" TEXT NOT NULL DEFAULT '[]', \"query_params_json\" TEXT NOT NULL DEFAULT '[]', "
      "\"body_type\" TEXT NOT NULL DEFAULT 'none', \"raw_content_type\" TEXT NOT NULL DEFAULT 'json', "
      "\"body_text\" TEXT NOT NULL DEFAULT '', \"form_fields_json\" TEXT NOT NULL DEFAULT '[]', "
      "\"url_encoded_fields_json\" TEXT NOT NULL DEFAULT '[]', \"graphql_query\" TEXT NOT NULL DEFAULT '', "
      "\"graphql_variables\" TEXT NOT NULL DEFAULT '{}', \"auth_type\" TEXT NOT NULL DEFAULT 'inherit', "
      "\"auth_config_json\" TEXT NOT NULL DEFAULT '{}', \"order_index\" INTEGER NOT NULL DEFAULT 0, "
      '"updated_at" INTEGER NOT NULL $_now)',
  'CREATE TABLE "environments" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, '
      '"is_active" INTEGER NOT NULL DEFAULT 0 CHECK ("is_active" IN (0, 1)))',
  'CREATE TABLE "environment_variables" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"environment_id" INTEGER NOT NULL REFERENCES environments (id) ON DELETE CASCADE, "key" TEXT NOT NULL, '
      '"value" TEXT NOT NULL DEFAULT \'\', "is_secret" INTEGER NOT NULL DEFAULT 0 CHECK ("is_secret" IN (0, 1)), '
      '"enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("enabled" IN (0, 1)), "order_index" INTEGER NOT NULL DEFAULT 0)',
  'CREATE TABLE "history_entries" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "request_id" INTEGER NULL, '
      '"method" TEXT NOT NULL, "url" TEXT NOT NULL, "status_code" INTEGER NULL, "duration_ms" INTEGER NULL, '
      '"response_headers_json" TEXT NOT NULL DEFAULT \'{}\', "response_body" BLOB NULL, "sent_at" INTEGER NOT NULL $_now)',
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
  'CREATE TABLE "entity_uids" ("kind" TEXT NOT NULL, "local_id" INTEGER NOT NULL, "uid" TEXT NOT NULL, '
      'PRIMARY KEY ("kind", "local_id"))',
  'CREATE UNIQUE INDEX entity_uids_uid ON entity_uids (uid)',
  'CREATE TABLE "git_links" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"collection_id" INTEGER NOT NULL UNIQUE REFERENCES collections (id) ON DELETE CASCADE, "provider" TEXT NOT NULL, '
      '"owner" TEXT NOT NULL, "repo" TEXT NOT NULL, "branch" TEXT NOT NULL, "base_path" TEXT NOT NULL DEFAULT \'\', '
      '"last_synced_sha" TEXT NULL, "last_synced_at" INTEGER NULL, '
      '"include_secrets" INTEGER NOT NULL DEFAULT 0 CHECK ("include_secrets" IN (0, 1)))',
  'CREATE TABLE "git_base_entries" ("link_id" INTEGER NOT NULL REFERENCES git_links (id) ON DELETE CASCADE, '
      '"uid" TEXT NOT NULL, "path" TEXT NOT NULL, "blob_sha" TEXT NOT NULL, "doc_json" TEXT NOT NULL, '
      'PRIMARY KEY ("link_id", "uid"))',
  'CREATE TABLE "setting_entries" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))',
  'CREATE TABLE "request_setting_entries" ("request_id" INTEGER NOT NULL REFERENCES requests (id) ON DELETE CASCADE, '
      '"settings_json" TEXT NOT NULL DEFAULT \'{}\', PRIMARY KEY ("request_id"))',
  'CREATE TABLE "entity_docs" ("kind" TEXT NOT NULL, "local_id" INTEGER NOT NULL, "markdown" TEXT NOT NULL DEFAULT \'\', '
      'PRIMARY KEY ("kind", "local_id"))',
  'CREATE TABLE "entity_tags" ("kind" TEXT NOT NULL, "local_id" INTEGER NOT NULL, "tag" TEXT NOT NULL, '
      'PRIMARY KEY ("kind", "local_id", "tag"))',
  'CREATE INDEX entity_tags_tag ON entity_tags (tag)',
];

const _rows = [
  "INSERT INTO collections (id, name) VALUES (1, 'Payments'), (2, 'Admin')",
  "INSERT INTO folders (id, collection_id, parent_folder_id, name) VALUES (1, 1, NULL, 'Users'), (2, 1, 1, 'Admins')",
  "INSERT INTO requests (id, collection_id, folder_id, name, method, url, headers_json) VALUES "
      "(5, 1, 2, 'List admins', 'get', 'https://api.test/admins', '[{\"key\":\"Accept\",\"value\":\"application/json\",\"enabled\":true}]'), "
      "(9, 2, NULL, 'Ping', 'head', 'https://admin.test/ping', '[]')",
  "INSERT INTO collection_variables (collection_id, key, value) VALUES (1, 'baseUrl', 'https://api.test')",
  "INSERT INTO collection_auth (collection_id, auth_json) VALUES (1, '{\"type\":\"bearer\",\"bearerToken\":\"old-token\"}')",
  "INSERT INTO request_scripts (request_id, assertions_json) VALUES (5, '[{\"type\":\"statusEquals\",\"expected\":\"200\"}]')",
  "INSERT INTO entity_docs (kind, local_id, markdown) VALUES ('folder', 1, 'Users folder')",
  "INSERT INTO entity_uids (kind, local_id, uid) VALUES ('request', 5, 'uid-5')",
  "INSERT INTO environments (id, name, is_active) VALUES (1, 'prod', 1)",
  "INSERT INTO history_entries (request_id, method, url, status_code) VALUES (5, 'GET', 'https://api.test/admins', 200)",
];

AppDatabase _openV4() => AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('PRAGMA foreign_keys = ON');
          for (final statement in [..._v4, ..._rows]) {
            raw.execute(statement);
          }
          raw.execute('PRAGMA user_version = 4');
        },
      ),
    );

Future<int> _scalar(AppDatabase db, String sql) async =>
    (await db.customSelect(sql).getSingle()).data.values.single as int;

Future<Set<String>> _tables(AppDatabase db) async =>
    (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map((r) => r.read<String>('name')).toSet();

Future<List<String>> _columns(AppDatabase db, String table) async =>
    (await db.customSelect('PRAGMA table_info("$table")').get()).map((r) => '${r.read<String>('name')} ${r.read<String>('type')} ${r.read<int>('notnull')} ${r.read<int>('pk')}').toList();

void main() {
  late AppDatabase db;

  setUp(() => db = _openV4());
  tearDown(() => db.close());

  test('the upgrade adds the tables of version 5 and stamps the current version', () async {
    final names = await _tables(db);

    expect(names, containsAll(['folder_defaults', 'collection_defaults', 'history_payloads']));
    expect(await _scalar(db, 'PRAGMA user_version'), db.schemaVersion);
    expect(db.schemaVersion, greaterThanOrEqualTo(5));
  });

  test('every row that was there survives, with its id', () async {
    expect(await _scalar(db, 'SELECT COUNT(*) FROM collections'), 2);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM folders'), 2);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM requests'), 2);
    final collections = await db.collectionsDao.watchAllCollections().first;
    expect(collections.map((c) => (c.id, c.name)), [(1, 'Payments'), (2, 'Admin')]);
    final request = (await db.requestsDao.findById(5))!;
    expect((request.name, request.folderId, request.url), ('List admins', 2, 'https://api.test/admins'));
    expect(request.headersJson, contains('"Accept"'));
    expect((await db.collectionAuthDao.findByCollection(1))!.authJson, contains('old-token'));
    expect(await _scalar(db, 'SELECT COUNT(*) FROM collection_variables'), 1);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM request_scripts'), 1);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM entity_docs'), 1);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM entity_uids'), 1);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM environments'), 1);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM history_entries'), 1);
  });

  test('the new tables start empty: a collection that predates defaults simply has none', () async {
    expect(await _scalar(db, 'SELECT COUNT(*) FROM folder_defaults'), 0);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM collection_defaults'), 0);

    final tree = await DefaultsRepositoryImpl(db).loadTree(1);

    expect(tree.folderDefaults, isEmpty);
    expect(tree.collection.headers, isEmpty);
    expect(tree.collection.hasTests, isFalse);
    expect(tree.folders.map((f) => f.name), ['Users', 'Admins']);
    expect(tree.collection.auth?.bearerToken, 'old-token', reason: 'the collection\'s own auth is read from collection_auth as before');
  });

  test('the upgraded tables work: defaults can be saved, and cascade with their folder and collection', () async {
    final repo = DefaultsRepositoryImpl(db);
    await repo.saveCollection(1, LevelDefaults(headers: [KeyValueItem(key: 'X-Tenant', value: 'acme')]));
    await repo.saveFolder(1, LevelDefaults(variables: [DefaultVariable(key: 'k', value: 'v')]));
    await repo.saveFolder(2, LevelDefaults(headers: [KeyValueItem(key: 'X-Inner', value: '1')]));
    expect(await _scalar(db, 'SELECT COUNT(*) FROM folder_defaults'), 2);
    expect(await _scalar(db, 'PRAGMA foreign_keys'), 1);

    await db.collectionsDao.deleteFolder(1);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM folder_defaults'), 0, reason: 'the folder and the one inside it are gone');

    await db.collectionsDao.deleteCollection(1);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM collection_defaults'), 0);
    expect(await _scalar(db, 'SELECT COUNT(*) FROM requests'), 1, reason: 'the other collection is untouched');
  });

  test('a request keeps working through the upgrade: it can still be saved and found in its folder', () async {
    await db.requestsDao.updateRequest(5, const RequestsCompanion(name: Value('Renamed')));

    expect((await db.requestsDao.findById(5))!.name, 'Renamed');
    expect((await db.requestsDao.findById(5))!.folderId, 2);
  });

  test('an upgraded database has the same columns in the new tables as a freshly created one', () async {
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    await fresh.customSelect('SELECT 1').get();

    for (final table in ['folder_defaults', 'collection_defaults']) {
      expect(await _columns(db, table), await _columns(fresh, table), reason: table);
    }
    expect(await _columns(db, 'folder_defaults'), [
      'folder_id INTEGER 1 1',
      "headers_json TEXT 1 0",
      "variables_json TEXT 1 0",
      "auth_json TEXT 1 0",
      "scripts_json TEXT 1 0",
    ]);
  });
}
