import 'package:flutter/foundation.dart' show compute;
import '../../../../core/errors/app_exception.dart';
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../collections/domain/repositories/collection_auth_repository.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../defaults/domain/entities/level_defaults.dart';
import '../../../defaults/domain/repositories/defaults_repository.dart';
import '../../../documentation/domain/entities/entity_kind.dart';
import '../../../documentation/domain/repositories/documentation_repository.dart';
import '../../../documentation/domain/repositories/tag_repository.dart';
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
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../entities/backup_export.dart';
import '../entities/import_format.dart';
import '../entities/import_summary.dart';
import '../repositories/git_state_store.dart';
import 'backup_codec.dart';
import 'backup_order.dart';
import 'collection_loader.dart';
import 'import_names.dart';

/// Exports all local data as one backup file and restores such a file: a
/// collection with its folders, variables, auth, requests (with their tests,
/// saved examples, per-request settings), and the descriptions and tags of the
/// collection, its folders and requests; plus environments and global variables.
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
  final RequestSettingsRepository _requestSettingsRepository;
  final DocumentationRepository _documentationRepository;
  final TagRepository _tagRepository;

  /// What links a collection to its Git repository. Optional: without it
  /// [snapshot] and [restore] simply never carry Git state.
  final GitStateStore? _gitState;

  /// Where a restore writes the defaults of the collections and folders it creates (reading them
  /// goes through the [CollectionLoader]). Without it a restore leaves them out.
  final DefaultsRepository? _defaults;

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
    this._requestSettingsRepository,
    this._documentationRepository,
    this._tagRepository, [
    this._gitState,
    this._defaults,
  ]);

  /// The workspace as data rather than text, for callers that persist it themselves.
  /// [includeGit] adds the Git link and sync state of linked collections, which
  /// a mirror of the database needs and a backup the user exports does not.
  Future<BackupSnapshot> snapshot({bool includeGit = false}) => _readSnapshot(includeGit: includeGit);

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

  Future<BackupSnapshot> _readSnapshot({bool includeGit = false}) async {
    final notes = {
      for (final kind in EntityKind.values)
        kind: (
          docs: await _documentationRepository.markdownByLocalId(kind),
          tags: await _tagRepository.tagsByLocalId(kind),
        ),
    };
    BackupNotes notesOf(EntityKind kind, int id) =>
        BackupNotes(description: notes[kind]!.docs[id] ?? '', tags: notes[kind]!.tags[id] ?? const []);

    final collections = <BackupCollection>[];
    for (final loaded in await _loader.loadAll()) {
      final gitState = includeGit
          ? await _gitState?.read(
              loaded.collection.id,
              folderIds: [for (final folder in loaded.folders) folder.id],
              requestIds: [for (final request in loaded.requests) request.id],
            )
          : null;
      final requests = <BackupRequest>[];
      for (final request in loaded.requests) {
        final scripts = await _scriptsRepository.get(request.id);
        final settings = await _requestSettingsRepository.get(request.id);
        requests.add(
          BackupRequest(
            request: request,
            scripts: scripts != null && _hasScripts(scripts) ? scripts : null,
            examples: await _exampleRepository.watchByRequest(request.id).first,
            settings: settings.isEmpty ? null : settings,
            notes: notesOf(EntityKind.request, request.id),
            uid: gitState?.requestUids[request.id],
          ),
        );
      }
      collections.add(
        BackupCollection(
          name: loaded.collection.name,
          auth: loaded.auth,
          variables: loaded.variables,
          folders: loaded.folders,
          requests: requests,
          notes: notesOf(EntityKind.collection, loaded.collection.id),
          folderNotes: {
            for (final folder in loaded.folders)
              if (!notesOf(EntityKind.folder, folder.id).isEmpty) folder.id: notesOf(EntityKind.folder, folder.id),
          },
          git: gitState?.git,
          uid: gitState?.collectionUid,
          folderUids: gitState?.folderUids ?? const {},
          // The collection's auth and variables are the two fields above, not part of these.
          defaults: LevelDefaults(
            headers: loaded.defaultsTree.collection.headers,
            assertions: loaded.defaultsTree.collection.assertions,
            extractors: loaded.defaultsTree.collection.extractors,
          ),
          folderDefaults: loaded.defaultsTree.folderDefaults,
        ),
      );
    }
    final environments = <BackupEnvironment>[];
    for (final environment in await _environmentRepository.watchAll().first) {
      environments.add(
        BackupEnvironment(
          name: environment.name,
          variables: await _environmentRepository.watchVariables(environment.id).first,
        ),
      );
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

  /// [restoreGit] re-links the collections the file says were linked to a Git
  /// repository, with their sync state. It is for a workspace being rebuilt from
  /// its own file; a backup the user imports into existing data never uses it,
  /// since two collections must not claim the same repository files.
  Future<ImportSummary> restore(String text, {bool restoreGit = false}) async {
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
        final counts = await _restoreCollection(collection, name, collectionIds, restoreGit);
        folders += counts.folders;
        requests += counts.requests;
      }

      final environmentNames = {for (final e in await _environmentRepository.watchAll().first) e.name};
      for (final environment in snapshot.environments) {
        final environmentId = await _environmentRepository.create(_uniqueName(environment.name, environmentNames));
        environmentIds.add(environmentId);
        for (final variable in environment.variables) {
          await _environmentRepository.upsertVariable(
            EnvironmentVariableEntity(
              id: 0,
              environmentId: environmentId,
              key: variable.key,
              value: variable.value,
              isSecret: variable.isSecret,
              enabled: variable.enabled,
            ),
          );
        }
      }

      final globalKeys = {for (final g in knownGlobals) g.key};
      for (final global in snapshot.globals) {
        if (!globalKeys.add(global.key)) {
          skippedGlobals++;
          continue;
        }
        await _globalVariableRepository.upsert(
          GlobalVariableEntity(
            id: 0,
            key: global.key,
            value: global.value,
            isSecret: global.isSecret,
            enabled: global.enabled,
          ),
        );
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
    bool restoreGit,
  ) async {
    final collectionId = await _collectionRepository.createCollection(name);
    createdIds.add(collectionId);
    final auth = collection.auth;
    if (auth != null) await _collectionAuthRepository.setAuthJson(collectionId, auth.toJsonString());
    for (final variable in collection.variables) {
      await _collectionVariableRepository.upsert(
        CollectionVariableEntity(
          id: 0,
          collectionId: collectionId,
          key: variable.key,
          value: variable.value,
          enabled: variable.enabled,
        ),
      );
    }
    await _restoreNotes(EntityKind.collection, collectionId, collection.notes);

    // One depth-first pass in the canonical order. Creating each folder and request as it comes appends it, so the
    // stored indexes reproduce the file's order, folders and requests interleaved. A folder whose parent is not in
    // the file, or that sits in a parent cycle, lands at the top level (see CollectionOrder).
    final folderIds = <int, int>{};
    final requestUids = <int, String>{};
    for (final entry in collection.canonicalOrder.entries) {
      final parentId = entry.parentId == null ? null : folderIds[entry.parentId];
      if (entry.isFolder) {
        final folder = collection.folders[entry.index];
        folderIds[folder.id] = await _createFolder(collectionId, parentId, folder.name);
      } else {
        await _restoreRequest(collectionId, collection.requests[entry.index], parentId, requestUids);
      }
    }
    for (final entry in collection.folderNotes.entries) {
      final folderId = folderIds[entry.key];
      if (folderId != null) await _restoreNotes(EntityKind.folder, folderId, entry.value);
    }
    final defaults = _defaults;
    if (defaults != null) {
      await defaults.saveCollection(collectionId, collection.defaults);
      for (final entry in collection.folderDefaults.entries) {
        final folderId = folderIds[entry.key];
        if (folderId != null) await defaults.saveFolder(folderId, entry.value);
      }
    }
    final git = collection.git;
    final gitState = _gitState;
    if (restoreGit && git != null && gitState != null) {
      await gitState.restore(
        collectionId,
        BackupGitState(
          git: git,
          collectionUid: collection.uid,
          folderUids: {
            for (final entry in collection.folderUids.entries)
              if (folderIds[entry.key] != null) folderIds[entry.key]!: entry.value,
          },
          requestUids: requestUids,
        ),
      );
    }
    return (folders: folderIds.length, requests: collection.requests.length);
  }

  Future<void> _restoreNotes(EntityKind kind, int id, BackupNotes notes) async {
    if (notes.description.isNotEmpty) await _documentationRepository.setMarkdown(kind, id, notes.description);
    if (notes.tags.isNotEmpty) await _tagRepository.setTags(kind, id, notes.tags);
  }

  Future<void> _restoreRequest(
    int collectionId,
    BackupRequest item,
    int? folderId,
    Map<int, String> requestUids,
  ) async {
    final source = item.request;
    final requestId = await _requestRepository.createRequest(
      collectionId: collectionId,
      folderId: folderId,
      name: source.name,
    );
    await _requestRepository.saveRequest(
      ApiRequestEntity(
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
      ),
    );
    final scripts = item.scripts;
    if (scripts != null) {
      await _scriptsRepository.save(
        RequestScriptsEntity(
          requestId: requestId,
          assertionsJson: scripts.assertionsJson,
          extractorsJson: scripts.extractorsJson,
        ),
      );
    }
    final settings = item.settings;
    if (settings != null) await _requestSettingsRepository.save(requestId, settings);
    await _restoreNotes(EntityKind.request, requestId, item.notes);
    if (item.uid != null) requestUids[requestId] = item.uid!;
    for (final example in item.examples) {
      await _exampleRepository.add(
        ResponseExampleEntity(
          id: 0,
          requestId: requestId,
          name: example.name,
          statusCode: example.statusCode,
          headers: example.headers,
          body: example.body,
          savedAt: example.savedAt,
        ),
      );
    }
  }

  Future<int> _createFolder(int collectionId, int? parentFolderId, String name) => _collectionRepository.createFolder(
    collectionId: collectionId,
    parentFolderId: parentFolderId,
    name: ImportNames.folder(name),
  );

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
