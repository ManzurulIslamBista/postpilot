import 'package:flutter/foundation.dart' show compute;
import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../git_sync/domain/services/secret_names.dart';
import '../entities/import_format.dart';
import '../entities/import_summary.dart';
import '../services/imported_collection_writer.dart';
import '../services/insomnia_parser.dart';

/// Recreates an Insomnia export (v4 JSON or v5 YAML) as new local data: one
/// collection per workspace with its folders, requests and base-environment
/// variables, plus one environment per Insomnia sub-environment (named
/// "Workspace - Environment", so the same name in two workspaces stays apart).
/// Nothing existing is touched; if the import fails midway everything it
/// created is removed again.
final class ImportInsomniaUseCase implements UseCase<ImportSummary, String> {
  final ImportedCollectionWriter _writer;
  final CollectionRepository _collectionRepository;
  final EnvironmentRepository _environmentRepository;

  const ImportInsomniaUseCase(this._writer, this._collectionRepository, this._environmentRepository);

  @override
  Future<ImportSummary> call(String text) async {
    // Off the UI isolate: a large export would otherwise freeze the window
    // before the import spinner ever paints.
    final parsed = await compute(InsomniaParser.parse, text);
    final collectionIds = <int>[];
    final environmentIds = <int>[];
    var folders = 0;
    var requests = 0;
    try {
      for (final workspace in parsed.workspaces) {
        final written = await _writer.write(workspace.collection);
        collectionIds.add(written.collectionId);
        folders += written.folders;
        requests += written.requests;
        for (final environment in workspace.environments) {
          final environmentId = await _environmentRepository.create('${workspace.collection.name} - ${environment.name}');
          environmentIds.add(environmentId);
          for (final variable in environment.variables) {
            await _environmentRepository.upsertVariable(EnvironmentVariableEntity(
              id: 0,
              environmentId: environmentId,
              key: variable.key,
              value: variable.value,
              // Insomnia has no secret flag. A variable named like a credential (an API key, a token) or
              // holding a known token is marked, so its value is not pushed to Git in plain text.
              isSecret: SecretNames.looksSecretKey(variable.key) || SecretNames.knownTokens(variable.value).isNotEmpty,
              enabled: variable.enabled,
            ));
          }
        }
      }
    } catch (_) {
      await _rollback(collectionIds, environmentIds);
      rethrow;
    }
    return ImportSummary(
      format: ImportFormat.insomnia,
      collectionIds: collectionIds,
      collectionName: parsed.workspaces.length == 1 ? parsed.workspaces.single.collection.name : null,
      folders: folders,
      requests: requests,
      environments: environmentIds.length,
    );
  }

  /// Best effort: the original failure is what the user needs to see.
  Future<void> _rollback(List<int> collectionIds, List<int> environmentIds) async {
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
  }
}
