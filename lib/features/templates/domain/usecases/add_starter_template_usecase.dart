import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../import_export/domain/services/imported_collection_writer.dart';
import '../starter_templates.dart';

final class AddedTemplate {
  final int collectionId;
  final int? environmentId;
  final int requests;
  const AddedTemplate(this.collectionId, this.environmentId, this.requests);
}

/// Adds a [StarterTemplate] to the workspace: its collection, and (when the
/// template needs one) an environment, which becomes the active one so the
/// first request already resolves its `{{variables}}`.
final class AddStarterTemplateUseCase {
  final ImportedCollectionWriter _writer;
  final EnvironmentRepository _environments;

  const AddStarterTemplateUseCase(this._writer, this._environments);

  Future<AddedTemplate> call(StarterTemplate template, {bool activateEnvironment = true}) async {
    final written = await _writer.write(template.collection);
    int? environmentId;
    final name = template.environmentName;
    if (name != null) {
      environmentId = await _environments.create(name);
      for (final v in template.environmentVariables) {
        await _environments.upsertVariable(
          EnvironmentVariableEntity(id: 0, environmentId: environmentId, key: v.key, value: v.value, isSecret: v.secret, enabled: true),
        );
      }
      if (activateEnvironment) await _environments.setActive(environmentId);
    }
    return AddedTemplate(written.collectionId, environmentId, written.requests);
  }
}
