import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/features/collections/domain/entities/collection_entity.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_auth_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_repository.dart';
import 'package:postpilot/features/collections/domain/repositories/collection_variable_repository.dart';
import 'package:postpilot/features/defaults/domain/entities/defaults_chain.dart';
import 'package:postpilot/features/defaults/domain/entities/level_defaults.dart';
import 'package:postpilot/features/defaults/domain/repositories/defaults_repository.dart';
import 'package:postpilot/features/defaults/domain/services/defaults_codec.dart';
import 'package:postpilot/features/documentation/domain/entities/entity_kind.dart';
import 'package:postpilot/features/documentation/domain/repositories/documentation_repository.dart';
import 'package:postpilot/features/documentation/domain/repositories/tag_repository.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/environments/domain/entities/global_variable_entity.dart';
import 'package:postpilot/features/environments/domain/repositories/environment_repository.dart';
import 'package:postpilot/features/environments/domain/repositories/global_variable_repository.dart';
import 'package:postpilot/features/import_export/domain/repositories/git_state_store.dart';
import 'package:postpilot/features/import_export/domain/services/backup_service.dart';
import 'package:postpilot/features/import_export/domain/services/collection_loader.dart';
import 'package:postpilot/features/import_export/domain/services/imported_collection_writer.dart';
import 'package:postpilot/features/request_builder/domain/entities/api_request_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_auth.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_scripts_entity.dart';
import 'package:postpilot/features/request_builder/domain/entities/response_example_entity.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/request_scripts_repository.dart';
import 'package:postpilot/features/request_builder/domain/repositories/response_example_repository.dart';
import 'package:postpilot/features/settings/domain/entities/request_settings.dart';
import 'package:postpilot/features/settings/domain/repositories/request_settings_repository.dart';

/// The repositories the import/export code works through. Implemented by the
/// in-memory [InMemoryDb] and, in the database test, by the real ones.
abstract interface class RepositoryBundle {
  CollectionRepository get collectionRepository;
  RequestRepository get requestRepository;
  CollectionVariableRepository get collectionVariableRepository;
  CollectionAuthRepository get collectionAuthRepository;
  RequestScriptsRepository get scriptsRepository;
  ResponseExampleRepository get exampleRepository;
  EnvironmentRepository get environmentRepository;
  GlobalVariableRepository get globalVariableRepository;
  RequestSettingsRepository get requestSettingsRepository;
  DocumentationRepository get documentationRepository;
  TagRepository get tagRepository;
}

/// The services and use cases built on a [RepositoryBundle], wired the way the
/// injector wires them.
extension ImportExportServices on RepositoryBundle {
  ImportedCollectionWriter get writer => ImportedCollectionWriter(
    collectionRepository,
    requestRepository,
    collectionVariableRepository,
    collectionAuthRepository,
  );

  /// The defaults of collections and folders, for the bundles that have them (the database-backed one).
  DefaultsRepository? get _defaults => this is DefaultsRepositoryHolder ? (this as DefaultsRepositoryHolder).defaultsRepository : null;

  CollectionLoader get loader => CollectionLoader(
    collectionRepository,
    requestRepository,
    collectionVariableRepository,
    collectionAuthRepository,
    _defaults,
  );

  BackupService get backupService => backupServiceWith(null);

  /// The same service, able to carry Git links through [gitState].
  BackupService backupServiceWith(GitStateStore? gitState) => BackupService(
    loader,
    collectionRepository,
    requestRepository,
    collectionVariableRepository,
    collectionAuthRepository,
    scriptsRepository,
    exampleRepository,
    environmentRepository,
    globalVariableRepository,
    requestSettingsRepository,
    documentationRepository,
    tagRepository,
    gitState,
    _defaults,
  );
}

/// A [RepositoryBundle] that also has the defaults repository (an extra interface, so the bundles
/// that predate defaults stay as they are).
abstract interface class DefaultsRepositoryHolder {
  DefaultsRepository get defaultsRepository;
}

/// All the tables the import/export code touches, in memory, behind the same
/// repository interfaces the app uses. Deleting a collection cascades like the
/// real foreign keys do, so rollback behaviour can be tested.
final class InMemoryDb implements RepositoryBundle, DefaultsRepositoryHolder {
  int _sequence = 0;
  int nextId() => ++_sequence;

  final collections = <CollectionEntity>[];
  final folders = <FolderEntity>[];
  final requests = <ApiRequestEntity>[];
  final variables = <CollectionVariableEntity>[];
  final collectionAuth = <int, String>{};
  final scripts = <int, RequestScriptsEntity>{};
  final examples = <ResponseExampleEntity>[];
  final environments = <EnvironmentEntity>[];
  final environmentVariables = <EnvironmentVariableEntity>[];
  final globals = <GlobalVariableEntity>[];
  final requestSettings = <int, RequestSettings>{};

  /// What collections and folders pass down to their requests (a collection's headers and tests; a folder's everything).
  final collectionDefaults = <int, LevelDefaults>{};
  final folderDefaults = <int, LevelDefaults>{};

  /// Descriptions and tags, keyed by `kind:id` (the real tables have no foreign key either).
  final descriptions = <String, String>{};
  final tags = <String, List<String>>{};

  /// Makes the n-th (1-based) call of that write throw, to exercise rollbacks.
  int? failSaveRequestOnCall;
  int? failCreateEnvironmentOnCall;
  int? failUpsertGlobalOnCall;
  int _saveRequestCalls = 0;
  int _createEnvironmentCalls = 0;
  int _upsertGlobalCalls = 0;

  bool get shouldFailSaveRequest => ++_saveRequestCalls == failSaveRequestOnCall;
  bool get shouldFailCreateEnvironment => ++_createEnvironmentCalls == failCreateEnvironmentOnCall;
  bool get shouldFailUpsertGlobal => ++_upsertGlobalCalls == failUpsertGlobalOnCall;

  void deleteCollection(int id) {
    collections.removeWhere((c) => c.id == id);
    for (final folder in folders.where((f) => f.collectionId == id)) {
      folderDefaults.remove(folder.id);
    }
    collectionDefaults.remove(id);
    folders.removeWhere((f) => f.collectionId == id);
    final removedRequests = requests.where((r) => r.collectionId == id).map((r) => r.id).toSet();
    requests.removeWhere((r) => r.collectionId == id);
    variables.removeWhere((v) => v.collectionId == id);
    collectionAuth.remove(id);
    scripts.removeWhere((requestId, _) => removedRequests.contains(requestId));
    examples.removeWhere((e) => removedRequests.contains(e.requestId));
  }

  void deleteEnvironment(int id) {
    environments.removeWhere((e) => e.id == id);
    environmentVariables.removeWhere((v) => v.environmentId == id);
  }

  @override
  InMemoryCollectionRepository get collectionRepository => InMemoryCollectionRepository(this);
  @override
  InMemoryRequestRepository get requestRepository => InMemoryRequestRepository(this);
  @override
  InMemoryCollectionVariableRepository get collectionVariableRepository => InMemoryCollectionVariableRepository(this);
  @override
  InMemoryCollectionAuthRepository get collectionAuthRepository => InMemoryCollectionAuthRepository(this);
  @override
  InMemoryRequestScriptsRepository get scriptsRepository => InMemoryRequestScriptsRepository(this);
  @override
  InMemoryResponseExampleRepository get exampleRepository => InMemoryResponseExampleRepository(this);
  @override
  InMemoryEnvironmentRepository get environmentRepository => InMemoryEnvironmentRepository(this);
  @override
  InMemoryGlobalVariableRepository get globalVariableRepository => InMemoryGlobalVariableRepository(this);
  @override
  InMemoryRequestSettingsRepository get requestSettingsRepository => InMemoryRequestSettingsRepository(this);
  @override
  InMemoryDocumentationRepository get documentationRepository => InMemoryDocumentationRepository(this);
  @override
  InMemoryTagRepository get tagRepository => InMemoryTagRepository(this);
  @override
  InMemoryDefaultsRepository get defaultsRepository => InMemoryDefaultsRepository(this);

  static String noteKey(EntityKind kind, int id) => '${kind.dbValue}:$id';

  /// The requests of one collection, in creation order.
  List<ApiRequestEntity> requestsOf(int collectionId) => requests.where((r) => r.collectionId == collectionId).toList();
}

final class InMemoryCollectionRepository implements CollectionRepository {
  final InMemoryDb db;
  InMemoryCollectionRepository(this.db);

  @override
  Stream<List<CollectionEntity>> watchCollections() => Stream.value([...db.collections]);

  @override
  Future<int> createCollection(String name) async {
    final id = db.nextId();
    db.collections.add(CollectionEntity(id: id, name: name));
    return id;
  }

  @override
  Future<void> deleteCollection(int id) async => db.deleteCollection(id);

  @override
  Stream<List<FolderEntity>> watchFolders(int collectionId) =>
      Stream.value(db.folders.where((f) => f.collectionId == collectionId).toList());

  @override
  Future<int> createFolder({required int collectionId, int? parentFolderId, required String name}) async {
    final id = db.nextId();
    db.folders.add(FolderEntity(id: id, collectionId: collectionId, parentFolderId: parentFolderId, name: name));
    return id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class InMemoryRequestRepository implements RequestRepository {
  final InMemoryDb db;
  InMemoryRequestRepository(this.db);

  @override
  Stream<List<RequestSummaryEntity>> watchByCollection(int collectionId) => Stream.value([
    for (final r in db.requests)
      if (r.collectionId == collectionId)
        RequestSummaryEntity(id: r.id, folderId: r.folderId, name: r.name, method: r.method),
  ]);

  @override
  Future<ApiRequestEntity?> findById(int id) async {
    for (final r in db.requests) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<int> createRequest({required int collectionId, int? folderId, required String name}) async {
    final id = db.nextId();
    db.requests.add(
      ApiRequestEntity(
        id: id,
        collectionId: collectionId,
        folderId: folderId,
        name: name,
        method: HttpMethod.get,
        url: '',
        headers: const [],
        queryParams: const [],
        body: RequestBody.empty,
        auth: const RequestAuth(),
      ),
    );
    return id;
  }

  @override
  Future<void> saveRequest(ApiRequestEntity request) async {
    if (db.shouldFailSaveRequest) throw StateError('disk full');
    final index = db.requests.indexWhere((r) => r.id == request.id);
    db.requests[index] = request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class InMemoryCollectionVariableRepository implements CollectionVariableRepository {
  final InMemoryDb db;
  InMemoryCollectionVariableRepository(this.db);

  @override
  Stream<List<CollectionVariableEntity>> watchByCollection(int collectionId) =>
      Stream.value(db.variables.where((v) => v.collectionId == collectionId).toList());

  /// Inserts when [variable.id] is 0 (or unknown), otherwise updates that row, like the real repository.
  @override
  Future<void> upsert(CollectionVariableEntity variable) async {
    final index = variable.id == 0 ? -1 : db.variables.indexWhere((v) => v.id == variable.id);
    final row = CollectionVariableEntity(
      id: index == -1 ? db.nextId() : variable.id,
      collectionId: variable.collectionId,
      key: variable.key,
      value: variable.value,
      enabled: variable.enabled,
    );
    if (index == -1) {
      db.variables.add(row);
    } else {
      db.variables[index] = row;
    }
  }

  @override
  Future<void> delete(int id) async => db.variables.removeWhere((v) => v.id == id);

  @override
  Future<Map<String, String>> getEnabledMap(int collectionId) async => {
    for (final v in db.variables)
      if (v.collectionId == collectionId && v.enabled) v.key: v.value,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class InMemoryCollectionAuthRepository implements CollectionAuthRepository {
  final InMemoryDb db;
  InMemoryCollectionAuthRepository(this.db);

  @override
  Future<String?> getAuthJson(int collectionId) async => db.collectionAuth[collectionId];

  @override
  Future<void> setAuthJson(int collectionId, String json) async => db.collectionAuth[collectionId] = json;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class InMemoryRequestScriptsRepository implements RequestScriptsRepository {
  final InMemoryDb db;
  InMemoryRequestScriptsRepository(this.db);

  @override
  Future<RequestScriptsEntity?> get(int requestId) async => db.scripts[requestId];

  @override
  Future<void> save(RequestScriptsEntity scripts) async => db.scripts[scripts.requestId] = scripts;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class InMemoryResponseExampleRepository implements ResponseExampleRepository {
  final InMemoryDb db;
  InMemoryResponseExampleRepository(this.db);

  @override
  Stream<List<ResponseExampleEntity>> watchByRequest(int requestId) =>
      Stream.value(db.examples.where((e) => e.requestId == requestId).toList());

  @override
  Future<int> add(ResponseExampleEntity example) async {
    final id = db.nextId();
    db.examples.add(
      ResponseExampleEntity(
        id: id,
        requestId: example.requestId,
        name: example.name,
        statusCode: example.statusCode,
        headers: example.headers,
        body: example.body,
        savedAt: example.savedAt,
      ),
    );
    return id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class InMemoryEnvironmentRepository implements EnvironmentRepository {
  final InMemoryDb db;
  InMemoryEnvironmentRepository(this.db);

  @override
  Stream<List<EnvironmentEntity>> watchAll() => Stream.value([...db.environments]);

  @override
  Future<int> create(String name) async {
    if (db.shouldFailCreateEnvironment) throw StateError('disk full');
    final id = db.nextId();
    db.environments.add(EnvironmentEntity(id: id, name: name, isActive: false));
    return id;
  }

  @override
  Future<void> delete(int id) async => db.deleteEnvironment(id);

  @override
  Stream<List<EnvironmentVariableEntity>> watchVariables(int environmentId) =>
      Stream.value(db.environmentVariables.where((v) => v.environmentId == environmentId).toList());

  @override
  Future<void> upsertVariable(EnvironmentVariableEntity variable) async {
    db.environmentVariables.add(
      EnvironmentVariableEntity(
        id: db.nextId(),
        environmentId: variable.environmentId,
        key: variable.key,
        value: variable.value,
        isSecret: variable.isSecret,
        enabled: variable.enabled,
      ),
    );
  }

  @override
  Future<Map<String, String>> getActiveVariables() async {
    final active = db.environments.where((e) => e.isActive).map((e) => e.id).toSet();
    return {
      for (final v in db.environmentVariables)
        if (active.contains(v.environmentId) && v.enabled) v.key: v.value,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class InMemoryGlobalVariableRepository implements GlobalVariableRepository {
  final InMemoryDb db;
  InMemoryGlobalVariableRepository(this.db);

  @override
  Stream<List<GlobalVariableEntity>> watchAll() => Stream.value([...db.globals]);

  @override
  Future<void> upsert(GlobalVariableEntity variable) async {
    if (db.shouldFailUpsertGlobal) throw StateError('disk full');
    db.globals.add(
      GlobalVariableEntity(
        id: db.nextId(),
        key: variable.key,
        value: variable.value,
        isSecret: variable.isSecret,
        enabled: variable.enabled,
      ),
    );
  }

  @override
  Future<void> delete(int id) async => db.globals.removeWhere((g) => g.id == id);

  @override
  Future<Map<String, String>> getEnabledMap() async => {
    for (final g in db.globals)
      if (g.enabled) g.key: g.value,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class InMemoryRequestSettingsRepository implements RequestSettingsRepository {
  final InMemoryDb db;
  InMemoryRequestSettingsRepository(this.db);

  @override
  Future<RequestSettings> get(int requestId) async => db.requestSettings[requestId] ?? RequestSettings.none;

  @override
  Future<void> save(int requestId, RequestSettings settings) async {
    if (settings.isEmpty) {
      db.requestSettings.remove(requestId);
    } else {
      db.requestSettings[requestId] = settings;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final class InMemoryDocumentationRepository implements DocumentationRepository {
  final InMemoryDb db;
  InMemoryDocumentationRepository(this.db);

  @override
  Future<String> markdownOf(EntityKind kind, int id) async => db.descriptions[InMemoryDb.noteKey(kind, id)] ?? '';

  @override
  Future<void> setMarkdown(EntityKind kind, int id, String text) async {
    if (text.isEmpty) {
      db.descriptions.remove(InMemoryDb.noteKey(kind, id));
    } else {
      db.descriptions[InMemoryDb.noteKey(kind, id)] = text;
    }
  }

  @override
  Future<Map<int, String>> markdownByLocalId(EntityKind kind) async => {
    for (final entry in db.descriptions.entries)
      if (entry.key.startsWith('${kind.dbValue}:')) int.parse(entry.key.split(':').last): entry.value,
  };
}

final class InMemoryTagRepository implements TagRepository {
  final InMemoryDb db;
  InMemoryTagRepository(this.db);

  @override
  Future<void> setTags(EntityKind kind, int id, List<String> tags) async {
    final clean = [
      for (final tag in tags)
        if (tag.trim().isNotEmpty) tag.trim(),
    ];
    if (clean.isEmpty) {
      db.tags.remove(InMemoryDb.noteKey(kind, id));
    } else {
      db.tags[InMemoryDb.noteKey(kind, id)] = clean;
    }
  }

  @override
  Future<Map<int, List<String>>> tagsByLocalId(EntityKind kind) async => {
    for (final entry in db.tags.entries)
      if (entry.key.startsWith('${kind.dbValue}:')) int.parse(entry.key.split(':').last): [...entry.value],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// What collections and folders pass down, kept in the [InMemoryDb] with the rest.
final class InMemoryDefaultsRepository implements DefaultsRepository {
  final InMemoryDb db;
  InMemoryDefaultsRepository(this.db);

  @override
  Future<DefaultsTree> loadTree(int collectionId) async {
    final collection = db.collections.where((c) => c.id == collectionId).firstOrNull;
    if (collection == null) return DefaultsTree(collectionName: '', collectionId: collectionId);
    final folders = [for (final f in db.folders) if (f.collectionId == collectionId) f];
    return DefaultsTree(
      collectionName: collection.name,
      collectionId: collectionId,
      collection: (db.collectionDefaults[collectionId] ?? LevelDefaults.empty)
          .withAuth(DefaultsCodec.decodeAuth(db.collectionAuth[collectionId])),
      folders: folders,
      folderDefaults: {
        for (final f in folders)
          if (db.folderDefaults[f.id] != null) f.id: db.folderDefaults[f.id]!,
      },
    );
  }

  @override
  Future<LevelDefaults> getCollection(int collectionId) async => db.collectionDefaults[collectionId] ?? LevelDefaults.empty;

  @override
  Future<void> saveCollection(int collectionId, LevelDefaults defaults) async {
    // Only the headers and tests are the collection's own here, as in the database.
    final own = LevelDefaults(headers: defaults.headers, assertions: defaults.assertions, extractors: defaults.extractors);
    if (own.isEmpty) {
      db.collectionDefaults.remove(collectionId);
    } else {
      db.collectionDefaults[collectionId] = own;
    }
  }

  @override
  Future<LevelDefaults> getFolder(int folderId) async => db.folderDefaults[folderId] ?? LevelDefaults.empty;

  @override
  Future<void> saveFolder(int folderId, LevelDefaults defaults) async {
    if (defaults.isEmpty) {
      db.folderDefaults.remove(folderId);
    } else {
      db.folderDefaults[folderId] = defaults;
    }
  }

  @override
  Future<int?> currentFolderId(int requestId, {int? fallback}) async {
    final stored = db.requests.where((r) => r.id == requestId).firstOrNull;
    return stored == null ? fallback : stored.folderId;
  }

  @override
  Stream<void> changes(int collectionId) => const Stream.empty();
}
