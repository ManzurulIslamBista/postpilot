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
import '../../../request_builder/domain/entities/request_scripts_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../../../scripting/data/models/scripts_json_codec.dart';
import '../entities/level_units.dart';
import '../entities/request_unit.dart';
import '../entities/unit_field.dart';
import '../entities/variable_units.dart';

/// Where the changes of a refactor are written.
abstract interface class RefactorWriter {
  /// Writes the [groups] of [target] over [current] (what is stored now). Returns, for every saved example that had to
  /// be saved again (the examples have no update), its position and the id of the new copy.
  Future<Map<int, int>> write(RefactorUnit current, RefactorUnit target, Set<String> groups);

  /// Deletes a variable row.
  Future<void> delete(RefactorUnit unit);

  /// Adds a deleted variable row back, as a new row with the same content.
  Future<void> recreate(RefactorUnit unit);
}

/// Writes through the same repositories the screens use (and so the same streams fire): the workplace file mirrors
/// the database from them, a Git-linked collection sees the rows change, an open list repaints.
final class RepositoryRefactorWriter implements RefactorWriter {
  final RequestRepository _requests;
  final RequestScriptsRepository _scripts;
  final ResponseExampleRepository _examples;
  final CollectionRepository _collections;
  final CollectionAuthRepository _collectionAuth;
  final CollectionVariableRepository _collectionVariables;
  final DefaultsRepository _defaults;
  final EnvironmentRepository _environments;
  final GlobalVariableRepository _globals;
  final DocumentationRepository _docs;
  final TagRepository _tags;

  const RepositoryRefactorWriter(
    this._requests,
    this._scripts,
    this._examples,
    this._collections,
    this._collectionAuth,
    this._collectionVariables,
    this._defaults,
    this._environments,
    this._globals,
    this._docs,
    this._tags,
  );

  @override
  Future<Map<int, int>> write(RefactorUnit current, RefactorUnit target, Set<String> groups) async {
    switch (target) {
      case RequestUnit():
        return _writeRequest(current as RequestUnit, target, groups);
      case CollectionUnit():
        await _writeCollection(target, groups);
      case FolderUnit():
        await _writeFolder(target, groups);
      case VariableRowUnit():
        await _writeRow(target);
      default:
        throw StateError('Cannot write ${target.key}');
    }
    return const {};
  }

  Future<Map<int, int>> _writeRequest(RequestUnit current, RequestUnit target, Set<String> groups) async {
    final replaced = <int, int>{};
    for (final group in groups) {
      switch (group) {
        case 'request':
          await _requests.saveRequest(target.request);
        case 'scripts':
          await _scripts.save(
            RequestScriptsEntity(
              requestId: target.id,
              assertionsJson: ScriptsJsonCodec.encodeAssertions(target.assertions),
              extractorsJson: ScriptsJsonCodec.encodeExtractors(target.extractors),
            ),
          );
        case 'doc':
          await _docs.setMarkdown(EntityKind.request, target.id, target.description);
        case 'tags':
          await _tags.setTags(EntityKind.request, target.id, target.tags);
        default:
          if (!group.startsWith('example.')) throw StateError('Unknown group $group of ${target.key}');
          final index = int.parse(group.substring('example.'.length));
          // There is no update: the new copy is added first, so a failure cannot lose the example.
          final newId = await _examples.add(target.examples[index]);
          await _examples.delete(current.examples[index].id);
          replaced[index] = newId;
      }
    }
    return replaced;
  }

  Future<void> _writeCollection(CollectionUnit unit, Set<String> groups) async {
    for (final group in groups) {
      switch (group) {
        case 'name':
          await _collections.renameCollection(unit.id, unit.collection.name);
        case 'doc':
          await _docs.setMarkdown(EntityKind.collection, unit.id, unit.description);
        case 'tags':
          await _tags.setTags(EntityKind.collection, unit.id, unit.tags);
        case 'auth':
          final auth = unit.auth;
          if (auth != null) await _collectionAuth.setAuthJson(unit.id, auth.toJsonString());
        case 'defaults':
          // Only the headers and tests are the collection's own here; its auth and variables have their own tables.
          await _defaults.saveCollection(
            unit.id,
            LevelDefaults(headers: unit.defaults.headers, assertions: unit.defaults.assertions, extractors: unit.defaults.extractors),
          );
        default:
          throw StateError('Unknown group $group of ${unit.key}');
      }
    }
  }

  Future<void> _writeFolder(FolderUnit unit, Set<String> groups) async {
    for (final group in groups) {
      switch (group) {
        case 'name':
          await _collections.renameFolder(unit.id, unit.folder.name);
        case 'doc':
          await _docs.setMarkdown(EntityKind.folder, unit.id, unit.description);
        case 'tags':
          await _tags.setTags(EntityKind.folder, unit.id, unit.tags);
        case 'defaults':
          await _defaults.saveFolder(unit.id, unit.defaults);
        default:
          throw StateError('Unknown group $group of ${unit.key}');
      }
    }
  }

  Future<void> _writeRow(VariableRowUnit unit) async {
    switch (unit) {
      case EnvironmentVariableUnit():
        await _environments.upsertVariable(unit.variable);
      case GlobalVariableUnit():
        await _globals.upsert(unit.variable);
      case CollectionVariableUnit():
        await _collectionVariables.upsert(unit.variable);
    }
  }

  @override
  Future<void> delete(RefactorUnit unit) async {
    switch (unit) {
      case EnvironmentVariableUnit():
        await _environments.deleteVariable(unit.id);
      case GlobalVariableUnit():
        await _globals.delete(unit.id);
      case CollectionVariableUnit():
        await _collectionVariables.delete(unit.id);
      default:
        throw StateError('${unit.key} is not a variable row');
    }
  }

  @override
  Future<void> recreate(RefactorUnit unit) async {
    switch (unit) {
      case EnvironmentVariableUnit(:final variable):
        await _environments.upsertVariable(
          EnvironmentVariableEntity(
            id: 0,
            environmentId: variable.environmentId,
            key: variable.key,
            value: variable.value,
            isSecret: variable.isSecret,
            enabled: variable.enabled,
          ),
        );
      case GlobalVariableUnit(:final variable):
        await _globals.upsert(
          GlobalVariableEntity(id: 0, key: variable.key, value: variable.value, isSecret: variable.isSecret, enabled: variable.enabled),
        );
      case CollectionVariableUnit(:final variable):
        await _collectionVariables.upsert(
          CollectionVariableEntity(
            id: 0,
            collectionId: variable.collectionId,
            key: variable.key,
            value: variable.value,
            enabled: variable.enabled,
          ),
        );
      default:
        throw StateError('${unit.key} is not a variable row');
    }
  }
}
