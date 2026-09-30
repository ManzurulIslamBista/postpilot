import 'package:flutter/foundation.dart' show compute;
import '../../../../core/errors/app_exception.dart';
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/entities/global_variable_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../environments/domain/repositories/global_variable_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/request_scripts_entity.dart';
import '../../../request_builder/domain/entities/response_example_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../entities/backup_export.dart';
import '../entities/import_format.dart';
import '../entities/import_summary.dart';
import 'backup_codec.dart';
import 'collection_loader.dart';

/// Exports all local data as one backup file and restores such a file.
///
/// A restore only ever adds: every collection and environment in the file is
/// created new (a name that is already taken gets a "(restored)" suffix), and
/// a global variable whose key already exists is skipped rather than
/// overwritten. Nothing existing is modified or deleted, and the active
/// environment is left alone. Everything goes through the repository
/// interfaces; if the restore fails midway, whatever it created is removed
/// again, so a retry doesn't pile duplicates on top.
final class BackupService {
  final CollectionLoader _loader;
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;
  final CollectionVariableRepository _collectionVariableRepository;
  final CollectionAuthRepository _collectionAuthRepository;
  final RequestScriptsRepository _scriptsRepository;
  final ResponseExampleRepository _exampleRepository;
  final EnvironmentRepository _environmentRepository;
  final GlobalVariableRepository _globalVariableRepository;

  const BackupService(
    this._loader,
    this._collectionRepository,
    this._requestRepository,
    this._collectionVariableRepository,
    this._collectionAuthRepository,
    this._scriptsRepository,
    this._exampleRepository,
    this._environmentRepository,
    this._globalVariableRepository,
  );

  Future<BackupExport> export() async {
    final snapshot = await _readSnapshot();
    return BackupExport(
      text: BackupCodec.encode(snapshot),
      collections: snapshot.collections.length,
      folders: snapshot.collections.fold(0, (sum, c) => sum + c.folders.length),
      requests: snapshot.collections.fold(0, (sum, c) => sum + c.requests.length),
      environments: snapshot.environments.length,
      globalVariables: snapshot.globals.length,
    );
  }

  Future<BackupSnapshot> _readSnapshot() async {
    final collections = <BackupCollection>[];
    for (final loaded in await _loader.loadAll()) {
      final requests = <BackupRequest>[];
      for (final request in loaded.requests) {
        final scripts = await _scriptsRepository.get(request.id);
        requests.add(BackupRequest(
          request: request,
          scripts: scripts != null && _hasScripts(scripts) ? scripts : null,
          examples: await _exampleRepository.watchByRequest(request.id).first,
        ));
      }
      collections.add(BackupCollection(
        name: loaded.collection.name,
        auth: loaded.auth,
        variables: loaded.variables,
        folders: loaded.folders,
        requests: requests,
      ));
    }
    final environments = <BackupEnvironment>[];
    for (final environment in await _environmentRepository.watchAll().first) {
      environments.add(BackupEnvironment(
        name: environment.name,
        variables: await _environmentRepository.watchVariables(environment.id).first,
      ));
    }
    return BackupSnapshot(
      exportedAt: DateTime.now(),
      collections: collections,
      environments: environments,
      globals: await _globalVariableRepository.watchAll().first,
    );
  }

  bool _hasScripts(RequestScriptsEntity scripts) =>
      scripts.assertionsJson.trim() != '[]' || scripts.extractorsJson.trim() != '[]';

  Future<ImportSummary> restore(String text) async {
    // Off the UI isolate: a large backup would otherwise freeze the window.
    final snapshot = await compute(BackupCodec.decode, text);
    if (snapshot.collections.isEmpty && snapshot.environments.isEmpty && snapshot.globals.isEmpty) {
      throw const ImportException('the backup holds no data.');
    }

    final collectionIds = <int>[];
    final environmentIds = <int>[];
    final knownGlobals = await _globalVariableRepository.watchAll().first;
    final preexistingGlobalIds = {for (final g in knownGlobals) g.id};
    var folders = 0;
    var requests = 0;
    var addedGlobals = 0;
    var skippedGlobals = 0;
    String? singleName;
    try {
      final collectionNames = {for (final c in await _collectionRepository.watchCollections().first) c.name};
      for (final collection in snapshot.collections) {
        final name = _uniqueName(collection.name, collectionNames);
        singleName = name;
        final counts = await _restoreCollection(collection, name, collectionIds);
        folders += counts.folders;
        requests += counts.requests;
      }

      final environmentNames = {for (final e in await _environmentRepository.watchAll().first) e.name};
      for (final environment in snapshot.environments) {
        final environmentId = await _environmentRepository.create(_uniqueName(environment.name, environmentNames));
        environmentIds.add(environmentId);
        for (final variable in environment.variables) {
          await _environmentRepository.upsertVariable(EnvironmentVariableEntity(
            id: 0,
            environmentId: environmentId,
            key: variable.key,
            value: variable.value,
            isSecret: variable.isSecret,
            enabled: variable.enabled,
          ));
        }
      }

      final globalKeys = {for (final g in knownGlobals) g.key};
      for (final global in snapshot.globals) {
        if (!globalKeys.add(global.key)) {
          skippedGlobals++;
          continue;
        }
        await _globalVariableRepository.upsert(GlobalVariableEntity(
          id: 0,
          key: global.key,
          value: global.value,
          isSecret: global.isSecret,
          enabled: global.enabled,
        ));
        addedGlobals++;
      }
    } catch (_) {
      await _rollback(collectionIds, environmentIds, preexistingGlobalIds);
      rethrow;
    }
    return ImportSummary(
      format: ImportFormat.backup,
      collectionIds: collectionIds,
      collectionName: collectionIds.length == 1 ? singleName : null,
      folders: folders,
      requests: requests,
      environments: environmentIds.length,
      globalVariables: addedGlobals,
      skipped: skippedGlobals,
    );
  }

  Future<({int folders, int requests})> _restoreCollection(
    BackupCollection collection,
    String name,
    List<int> createdIds,
  ) async {
    final collectionId = await _collectionRepository.createCollection(name);
    createdIds.add(collectionId);
    final auth = collection.auth;
    if (auth != null) await _collectionAuthRepository.setAuthJson(collectionId, auth.toJsonString());
    for (final variable in collection.variables) {
      await _collectionVariableRepository.upsert(CollectionVariableEntity(
        id: 0,
        collectionId: collectionId,
        key: variable.key,
        value: variable.value,
        enabled: variable.enabled,
      ));
    }

    final folderIds = await _restoreFolders(collectionId, collection.folders);
    for (final item in collection.requests) {
      final source = item.request;
      final folderId = source.folderId == null ? null : folderIds[source.folderId];
      final requestId = await _requestRepository.createRequest(
        collectionId: collectionId,
        folderId: folderId,
        name: source.name,
      );
      await _requestRepository.saveRequest(ApiRequestEntity(
        id: requestId,
        collectionId: collectionId,
        folderId: folderId,
        name: source.name,
        method: source.method,
        url: source.url,
        headers: source.headers,
        queryParams: source.queryParams,
        body: source.body,
        auth: source.auth,
      ));
      final scripts = item.scripts;
      if (scripts != null) {
        await _scriptsRepository.save(RequestScriptsEntity(
          requestId: requestId,
          assertionsJson: scripts.assertionsJson,
          extractorsJson: scripts.extractorsJson,
        ));
      }
      for (final example in item.examples) {
        await _exampleRepository.add(ResponseExampleEntity(
          id: 0,
          requestId: requestId,
          name: example.name,
          statusCode: example.statusCode,
          headers: example.headers,
          body: example.body,
          savedAt: example.savedAt,
        ));
      }
    }
    return (folders: folderIds.length, requests: collection.requests.length);
  }

  /// Creates [folders] parents-first and returns file id -> new id. A folder
  /// whose parent isn't in the file, or that sits in a parent cycle, goes to
  /// the collection's top level.
  Future<Map<int, int>> _restoreFolders(int collectionId, List<FolderEntity> folders) async {
    final knownIds = {for (final f in folders) f.id};
    final created = <int, int>{};
    var pending = [...folders];
    while (pending.isNotEmpty) {
      final blocked = <FolderEntity>[];
      for (final folder in pending) {
        final parent = folder.parentFolderId;
        final waitsForParent = parent != null && knownIds.contains(parent) && !created.containsKey(parent);
        if (waitsForParent) {
          blocked.add(folder);
        } else {
          created[folder.id] = await _createFolder(collectionId, parent == null ? null : created[parent], folder.name);
        }
      }
      if (blocked.length == pending.length) {
        for (final folder in blocked) {
          created[folder.id] = await _createFolder(collectionId, null, folder.name);
        }
        break;
      }
      pending = blocked;
    }
    return created;
  }

  Future<int> _createFolder(int collectionId, int? parentFolderId, String name) =>
      _collectionRepository.createFolder(collectionId: collectionId, parentFolderId: parentFolderId, name: name);

  /// [name] itself when free, else "name (restored)", "name (restored 2)", ...;
  /// the chosen name is added to [taken].
  String _uniqueName(String name, Set<String> taken) {
    var candidate = name;
    for (var n = 1; taken.contains(candidate); n++) {
      candidate = n == 1 ? '$name (restored)' : '$name (restored $n)';
    }
    taken.add(candidate);
    return candidate;
  }

  /// Best effort: the original failure is what the user needs to see.
  Future<void> _rollback(List<int> collectionIds, List<int> environmentIds, Set<int> preexistingGlobalIds) async {
    for (final id in collectionIds) {
      try {
        await _collectionRepository.deleteCollection(id);
      } catch (_) {}
    }
    for (final id in environmentIds) {
      try {
        await _environmentRepository.delete(id);
      } catch (_) {}
    }
    try {
      for (final global in await _globalVariableRepository.watchAll().first) {
        if (!preexistingGlobalIds.contains(global.id)) await _globalVariableRepository.delete(global.id);
      }
    } catch (_) {}
  }
}
