import '../../../collections/domain/entities/collection_entity.dart';
import '../../../defaults/domain/entities/level_defaults.dart';
import '../../../documentation/domain/entities/entity_kind.dart';
import '../../../documentation/domain/repositories/documentation_repository.dart';
import '../../../documentation/domain/repositories/tag_repository.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../environments/domain/repositories/global_variable_repository.dart';
import '../../../import_export/domain/services/collection_loader.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../../../scripting/data/models/scripts_json_codec.dart';
import '../entities/level_units.dart';
import '../entities/request_unit.dart';
import '../entities/unit_field.dart';
import '../entities/variable_units.dart';
import '../entities/workspace_snapshot.dart';

/// Where the tools read the workspace from.
abstract interface class WorkspaceSource {
  Future<WorkspaceSnapshot> read();
}

/// Reads every collection, folder, request, variable, test, note, tag and saved example through the repositories, the
/// way a backup does, into the units the tools work on.
final class WorkspaceReader implements WorkspaceSource {
  final CollectionLoader _loader;
  final EnvironmentRepository _environments;
  final GlobalVariableRepository _globals;
  final RequestScriptsRepository _scripts;
  final ResponseExampleRepository _examples;
  final DocumentationRepository _docs;
  final TagRepository _tags;

  const WorkspaceReader(this._loader, this._environments, this._globals, this._scripts, this._examples, this._docs, this._tags);

  @override
  Future<WorkspaceSnapshot> read() async {
    final notes = {
      for (final kind in EntityKind.values)
        kind: (docs: await _docs.markdownByLocalId(kind), tags: await _tags.tagsByLocalId(kind)),
    };
    final units = <RefactorUnit>[];
    for (final loaded in await _loader.loadAll()) {
      final collection = loaded.collection;
      final tree = loaded.defaultsTree;
      units.add(
        CollectionUnit(
          collection: collection,
          description: notes[EntityKind.collection]!.docs[collection.id] ?? '',
          tags: notes[EntityKind.collection]!.tags[collection.id] ?? const [],
          auth: loaded.auth,
          defaults: LevelDefaults(
            headers: tree.collection.headers,
            assertions: tree.collection.assertions,
            extractors: tree.collection.extractors,
          ),
        ),
      );
      for (final variable in loaded.variables) {
        units.add(CollectionVariableUnit(variable: variable, collectionName: collection.name));
      }

      final folderTrails = _folderTrails(collection, loaded.folders);
      final byFolder = <int?, List<ApiRequestEntity>>{};
      for (final request in loaded.requests) {
        byFolder.putIfAbsent(request.folderId, () => []).add(request);
      }
      final known = {for (final f in loaded.folders) f.id};

      Future<RequestUnit> requestUnit(ApiRequestEntity request, List<String> parentTrail) async {
        final scripts = await _scripts.get(request.id);
        return RequestUnit(
          request: request,
          parentTrail: parentTrail,
          assertions: scripts == null ? const [] : ScriptsJsonCodec.decodeAssertions(scripts.assertionsJson),
          extractors: scripts == null ? const [] : ScriptsJsonCodec.decodeExtractors(scripts.extractorsJson),
          hasScripts: scripts != null,
          description: notes[EntityKind.request]!.docs[request.id] ?? '',
          tags: notes[EntityKind.request]!.tags[request.id] ?? const [],
          examples: await _examples.watchByRequest(request.id).first,
        );
      }

      // The collection's own requests, then each folder with its requests. A request whose folder is gone is the
      // collection's, as the sidebar shows it.
      final orphans = [
        for (final entry in byFolder.entries)
          if (entry.key != null && !known.contains(entry.key)) ...entry.value,
      ];
      for (final request in [...?byFolder[null], ...orphans]) {
        units.add(await requestUnit(request, [collection.name]));
      }
      for (final folder in loaded.folders) {
        final trail = folderTrails[folder.id]!;
        units.add(
          FolderUnit(
            folder: folder,
            parentTrail: trail.sublist(0, trail.length - 1),
            description: notes[EntityKind.folder]!.docs[folder.id] ?? '',
            tags: notes[EntityKind.folder]!.tags[folder.id] ?? const [],
            defaults: tree.folderDefaults[folder.id] ?? LevelDefaults.empty,
          ),
        );
        for (final request in byFolder[folder.id] ?? const <ApiRequestEntity>[]) {
          units.add(await requestUnit(request, trail));
        }
      }
    }

    for (final environment in await _environments.watchAll().first) {
      for (final variable in await _environments.watchVariables(environment.id).first) {
        units.add(EnvironmentVariableUnit(variable: variable, environmentName: environment.name));
      }
    }
    for (final variable in await _globals.watchAll().first) {
      units.add(GlobalVariableUnit(variable: variable));
    }
    return WorkspaceSnapshot(units);
  }

  /// Folder id to the names from the collection down to the folder. A folder inside a parent loop (damaged data) ends
  /// the walk at the point where it would repeat.
  static Map<int, List<String>> _folderTrails(CollectionEntity collection, List<FolderEntity> folders) {
    final byId = {for (final f in folders) f.id: f};
    final trails = <int, List<String>>{};
    for (final folder in folders) {
      final names = <String>[];
      final seen = <int>{};
      FolderEntity? current = folder;
      while (current != null && seen.add(current.id)) {
        names.insert(0, current.name);
        current = current.parentFolderId == null ? null : byId[current.parentFolderId];
      }
      trails[folder.id] = [collection.name, ...names];
    }
    return trails;
  }
}
