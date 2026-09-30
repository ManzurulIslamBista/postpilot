import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables/collections_table.dart';
import 'tables/requests_table.dart';
import 'tables/environments_table.dart';
import 'tables/history_table.dart';
import 'tables/global_variables_table.dart';
import 'tables/collection_variables_table.dart';
import 'tables/collection_auth_table.dart';
import 'tables/request_scripts_table.dart';
import 'tables/response_examples_table.dart';
import 'tables/entity_uids_table.dart';
import 'tables/git_links_table.dart';
import 'tables/setting_entries_table.dart';
import 'tables/request_settings_table.dart';
import 'tables/entity_docs_table.dart';
import 'tables/entity_tags_table.dart';
import 'daos/collections_dao.dart';
import 'daos/requests_dao.dart';
import 'daos/environments_dao.dart';
import 'daos/history_dao.dart';
import 'daos/global_variables_dao.dart';
import 'daos/collection_variables_dao.dart';
import 'daos/collection_auth_dao.dart';
import 'daos/request_scripts_dao.dart';
import 'daos/response_examples_dao.dart';
import 'daos/entity_uids_dao.dart';
import 'daos/git_links_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/request_settings_dao.dart';
import 'daos/entity_docs_dao.dart';
import 'daos/entity_tags_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Collections,
    Folders,
    Requests,
    Environments,
    EnvironmentVariables,
    HistoryEntries,
    GlobalVariables,
    CollectionVariables,
    CollectionAuth,
    RequestScripts,
    ResponseExamples,
    EntityUids,
    GitLinks,
    GitBaseEntries,
    SettingEntries,
    RequestSettingEntries,
    EntityDocs,
    EntityTags,
  ],
  daos: [
    CollectionsDao,
    RequestsDao,
    EnvironmentsDao,
    HistoryDao,
    GlobalVariablesDao,
    CollectionVariablesDao,
    CollectionAuthDao,
    RequestScriptsDao,
    ResponseExamplesDao,
    EntityUidsDao,
    GitLinksDao,
    SettingsDao,
    RequestSettingsDao,
    EntityDocsDao,
    EntityTagsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  // NOTE: pre-release schema change — `requests` is dropped and recreated
  // (losing saved requests) rather than migrated column-by-column, because
  // `Migrator.addColumn`'s ALTER TABLE statement reproducibly crashes the
  // drift web worker on this project (confirmed: a fresh IndexedDB with no
  // upgrade path has zero errors; addColumn during onUpgrade always throws
  // inside drift_worker.js). createTable/deleteTable are proven to work
  // since createAll() already uses them for first-run database creation.
  // Once there's real user data to protect, this needs a real fix (likely
  // a drift issue to file) instead of a drop-and-recreate.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.deleteTable(requests.actualTableName);
            await m.createTable(requests);
          }
          if (from < 3) {
            await m.createTable(globalVariables);
            await m.createTable(collectionVariables);
            await m.createIndex(collectionVariablesCollectionId);
            await m.createTable(collectionAuth);
            await m.createTable(requestScripts);
            await m.createTable(responseExamples);
            await m.createIndex(responseExamplesRequestId);
          }
          if (from < 4) {
            await m.createTable(entityUids);
            await m.createIndex(entityUidsUid);
            await m.createTable(gitLinks);
            await m.createTable(gitBaseEntries);
            await m.createTable(settingEntries);
            await m.createTable(requestSettingEntries);
            await m.createTable(entityDocs);
            await m.createTable(entityTags);
            await m.createIndex(entityTagsTag);
          }
        },
        // SQLite skips every ON DELETE CASCADE / SET NULL unless this is set on each connection.
        beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
      );

  // On web, sqlite3.wasm and drift_worker.js live in web/ (see web/drift_worker.dart
  // for the worker source — recompile it with `dart compile js` if it changes).
  static QueryExecutor _openConnection() => driftDatabase(
        name: 'postpilot',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      );
}
