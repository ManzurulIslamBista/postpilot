import 'package:drift/drift.dart';
import 'connection/app_connection.dart';
import 'migrations/create_missing_schema.dart';
import 'migrations/rebuild_table_keeping_rows.dart';
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
import 'tables/folder_defaults_table.dart';
import 'tables/collection_defaults_table.dart';
import 'tables/history_payloads_table.dart';
import 'tables/run_records_table.dart';
import 'tables/request_baselines_table.dart';
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
import 'daos/folder_defaults_dao.dart';
import 'daos/collection_defaults_dao.dart';
import 'daos/history_payloads_dao.dart';
import 'daos/run_records_dao.dart';
import 'daos/request_baselines_dao.dart';

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
    FolderDefaults,
    CollectionDefaults,
    HistoryPayloads,
    RunRecords,
    RequestBaselines,
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
    FolderDefaultsDao,
    CollectionDefaultsDao,
    HistoryPayloadsDao,
    RunRecordsDao,
    RequestBaselinesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  /// Empties everything a workplace owns (collections, folders, requests and
  /// all that hangs off them, environments, globals). `entity_docs`,
  /// `entity_tags` and `entity_uids` key their rows by `(kind, id)` without a
  /// foreign key, so deleting the entities does not remove them; they are
  /// cleared explicitly or the next workplace would show the last one's tags.
  Future<void> clearWorkplaceData() async {
    await transaction(() async {
      await delete(responseExamples).go();
      await delete(requestScripts).go();
      await delete(requestSettingEntries).go();
      await delete(folderDefaults).go();
      await delete(collectionDefaults).go();
      await delete(requests).go();
      await delete(folders).go();
      await delete(collectionVariables).go();
      await delete(collectionAuth).go();
      await delete(gitBaseEntries).go();
      await delete(gitLinks).go();
      await delete(collections).go();
      await delete(environmentVariables).go();
      await delete(environments).go();
      await delete(globalVariables).go();
      await delete(entityDocs).go();
      await delete(entityTags).go();
      await delete(entityUids).go();
    });
  }

  /// Emits whenever a table [clearWorkplaceData] empties changes, which is
  /// exactly when the workplace's `workspace.json` is out of date.
  Stream<void> workplaceDataChanges() => tableUpdates(
    TableUpdateQuery.onAllTables([
      collections,
      folders,
      requests,
      environments,
      environmentVariables,
      globalVariables,
      collectionVariables,
      collectionAuth,
      requestScripts,
      responseExamples,
      requestSettingEntries,
      folderDefaults,
      collectionDefaults,
      entityDocs,
      entityTags,
      // A Git link, its last-synced base and the uids move on every connect,
      // pull and push, and the workspace file carries them.
      gitLinks,
      gitBaseEntries,
      entityUids,
    ]),
  );

  @override
  int get schemaVersion => 6;

  // NOTE: never use `Migrator.addColumn` here: its ALTER TABLE statement
  // reproducibly crashes the drift web worker on this project (confirmed: a
  // fresh IndexedDB with no upgrade path has zero errors; addColumn during
  // onUpgrade always throws inside drift_worker.js). createTable/deleteTable
  // are proven to work since createAll() already uses them for first-run
  // database creation. A table whose columns changed is therefore rebuilt
  // with rebuildTableKeepingRows (create the new one, copy the shared
  // columns, drop the old one, all in one transaction) so no saved request
  // is ever lost; adding a plain new table stays a createTable.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      // v1's `requests` had another column set. The shape check also catches an old v2/v3 table that
      // predates a column, which would otherwise fail every query the DAOs run.
      if (from < 2 || await tableLacksColumns(this, requests)) {
        await rebuildTableKeepingRows(this, m, requests);
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
      if (from < 5) {
        await m.createTable(folderDefaults);
        await m.createTable(collectionDefaults);
        await m.createTable(historyPayloads);
      }
      if (from < 6) {
        await m.createTable(runRecords);
        await m.createTable(requestBaselines);
      }
    },
    // A database in the browser whose version number was lost (see beforeOpen) comes back as "new" with its tables in
    // place: createAll would fail on the first index that exists, and every query after that with it.
    onCreate: (m) async => await hasAppTables(this) ? createMissingSchema(this, m) : m.createAll(),
    beforeOpen: (details) async {
      // SQLite skips every ON DELETE CASCADE / SET NULL unless this is set on each connection.
      await customStatement('PRAGMA foreign_keys = ON');
      // Drift writes the new version itself after this callback, but the browser's IndexedDB file system only saves
      // after a statement that goes through the executor: a visit with no write left the database "unversioned", and
      // the next start tried to create every table again. Writing it here saves it with the schema it belongs to.
      if (details.wasCreated || details.hadUpgrade) await customStatement('PRAGMA user_version = $schemaVersion');
    },
  );

  // The platform's connection lives in connection/: a SQLite file natively, and on
  // the web SQLite-in-WebAssembly (sqlite3.wasm and drift_worker.js live in web/).
  static QueryExecutor _openConnection() => openAppConnection();
}
