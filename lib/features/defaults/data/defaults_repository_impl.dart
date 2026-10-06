import 'package:drift/drift.dart' show TableUpdateQuery, Value;
import '../../../core/database/app_database.dart';
import '../../collections/domain/entities/collection_entity.dart';
import '../domain/entities/defaults_chain.dart';
import '../domain/entities/level_defaults.dart';
import '../domain/repositories/defaults_repository.dart';
import '../domain/services/defaults_codec.dart';

/// [DefaultsRepository] over `folder_defaults` and `collection_defaults`. The collection's auth is
/// read from `collection_auth` when a whole tree is loaded, never written from here.
final class DefaultsRepositoryImpl implements DefaultsRepository {
  final AppDatabase _db;
  const DefaultsRepositoryImpl(this._db);

  @override
  Future<DefaultsTree> loadTree(int collectionId) async {
    final collection = await (_db.select(_db.collections)..where((t) => t.id.equals(collectionId))).getSingleOrNull();
    if (collection == null) return DefaultsTree(collectionName: '', collectionId: collectionId);

    final folderRows = await (_db.select(_db.folders)..where((t) => t.collectionId.equals(collectionId))).get();
    final own = await _db.collectionDefaultsDao.findByCollection(collectionId);
    final auth = await _db.collectionAuthDao.findByCollection(collectionId);
    final folderDefaults = await _db.folderDefaultsDao.allForCollection(collectionId);

    return DefaultsTree(
      collectionName: collection.name,
      collectionId: collectionId,
      collection: _collectionLevel(own).withAuth(DefaultsCodec.decodeAuth(auth?.authJson)),
      folders: [
        for (final f in folderRows)
          FolderEntity(id: f.id, collectionId: f.collectionId, parentFolderId: f.parentFolderId, name: f.name),
      ],
      folderDefaults: {for (final row in folderDefaults) row.folderId: _folderLevel(row)}
        ..removeWhere((_, level) => level.isEmpty),
    );
  }

  @override
  Future<LevelDefaults> getCollection(int collectionId) async =>
      _collectionLevel(await _db.collectionDefaultsDao.findByCollection(collectionId));

  @override
  Future<void> saveCollection(int collectionId, LevelDefaults defaults) async {
    if (defaults.headers.isEmpty && !defaults.hasTests) {
      await _db.collectionDefaultsDao.deleteForCollection(collectionId);
      return;
    }
    await _db.collectionDefaultsDao.upsert(
      CollectionDefaultsCompanion(
        collectionId: Value(collectionId),
        headersJson: Value(DefaultsCodec.encodeHeaders(defaults.headers)),
        scriptsJson: Value(DefaultsCodec.encodeScripts(defaults.assertions, defaults.extractors)),
      ),
    );
  }

  @override
  Future<LevelDefaults> getFolder(int folderId) async =>
      _folderLevel(await _db.folderDefaultsDao.findByFolder(folderId));

  @override
  Future<void> saveFolder(int folderId, LevelDefaults defaults) async {
    if (defaults.isEmpty) {
      await _db.folderDefaultsDao.deleteForFolder(folderId);
      return;
    }
    await _db.folderDefaultsDao.upsert(
      FolderDefaultsCompanion(
        folderId: Value(folderId),
        headersJson: Value(DefaultsCodec.encodeHeaders(defaults.headers)),
        variablesJson: Value(DefaultsCodec.encodeVariables(defaults.variables)),
        authJson: Value(DefaultsCodec.encodeAuth(defaults.auth)),
        scriptsJson: Value(DefaultsCodec.encodeScripts(defaults.assertions, defaults.extractors)),
      ),
    );
  }

  @override
  Future<int?> currentFolderId(int requestId, {int? fallback}) async {
    final row = await _db.requestsDao.findById(requestId);
    return row == null ? fallback : row.folderId;
  }

  @override
  Stream<void> changes(int collectionId) => _db
      .tableUpdates(TableUpdateQuery.onAllTables([_db.folderDefaults, _db.collectionDefaults, _db.collectionAuth, _db.folders]))
      .map((_) {});

  static LevelDefaults _collectionLevel(CollectionDefault? row) {
    if (row == null) return LevelDefaults.empty;
    final tests = DefaultsCodec.decodeScripts(row.scriptsJson);
    return LevelDefaults(
      headers: DefaultsCodec.decodeHeaders(row.headersJson),
      assertions: tests.assertions,
      extractors: tests.extractors,
    );
  }

  static LevelDefaults _folderLevel(FolderDefault? row) {
    if (row == null) return LevelDefaults.empty;
    final tests = DefaultsCodec.decodeScripts(row.scriptsJson);
    return LevelDefaults(
      headers: DefaultsCodec.decodeHeaders(row.headersJson),
      variables: DefaultsCodec.decodeVariables(row.variablesJson),
      auth: DefaultsCodec.decodeAuth(row.authJson),
      assertions: tests.assertions,
      extractors: tests.extractors,
    );
  }
}
