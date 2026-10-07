import '../../../../core/errors/app_exception.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../import_export/domain/entities/imported_collection.dart';
import '../../../import_export/domain/services/imported_collection_writer.dart';
import '../../../request_builder/domain/entities/request_scripts_entity.dart';
import '../../../request_builder/domain/entities/response_example_entity.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../../../scripting/data/models/scripts_json_codec.dart';
import '../../../scripting/domain/entities/assertion_entity.dart';
import '../services/recording_collection_builder.dart';

/// What was created from a recording, for the success message.
final class RecordedCollectionResult {
  final int collectionId;
  final String collectionName;
  final int requests;
  final int folders;
  final int examples;
  final int? environmentId;
  final String? environmentName;

  /// One sentence per thing that was left out or changed, plus what the person has to do next.
  final List<String> notes;

  const RecordedCollectionResult({
    required this.collectionId,
    required this.collectionName,
    required this.requests,
    required this.folders,
    required this.examples,
    required this.environmentId,
    required this.environmentName,
    required this.notes,
  });
}

/// Writes a [RecordingPlan]: the collection through [ImportedCollectionWriter] (so the order of the requests and the
/// rollback on failure are the importers' own), their saved examples and status checks, and an environment holding `baseUrl`
/// and the secret variables, empty. The environment is not activated: that is the person's switch to make.
final class CreateCollectionFromRecordingUseCase {
  final ImportedCollectionWriter _writer;
  final EnvironmentRepository _environments;
  final ResponseExampleRepository _examples;
  final RequestScriptsRepository _scripts;
  final DateTime Function() _now;

  CreateCollectionFromRecordingUseCase(
    this._writer,
    this._environments,
    this._examples,
    this._scripts, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  Future<RecordedCollectionResult> call(RecordingPlan plan) async {
    if (plan.isEmpty) {
      throw const ImportException('the recording holds no call that can be turned into a request. Use the app, then try again.');
    }
    final byRequest = Map<ImportedRequest, PlannedRequest>.identity();
    for (final planned in plan.requests) {
      byRequest[planned.request] = planned;
    }

    // The environment first: the writer removes a half-written collection by itself, so a failure there only has the
    // environment left to clean up.
    final environmentName = await _freeEnvironmentName(plan.environmentName);
    final environmentId = await _environments.create(environmentName);
    final WrittenCollection written;
    try {
      for (final variable in plan.environmentVariables) {
        await _environments.upsertVariable(EnvironmentVariableEntity(
          id: 0,
          environmentId: environmentId,
          key: variable.key,
          value: variable.value,
          isSecret: variable.secret,
          enabled: true,
        ));
      }
      written = await _writer.write(plan.collection, onRequestWritten: (request, requestId) async {
        final planned = byRequest[request];
        if (planned == null) return;
        for (final example in planned.examples) {
          await _examples.add(ResponseExampleEntity(
            id: 0,
            requestId: requestId,
            name: example.name,
            statusCode: example.status,
            headers: {...example.headers, if (example.truncated) ResponseExampleEntity.truncatedHeader: 'true'},
            body: example.body,
            savedAt: _now(),
          ));
        }
        final status = planned.assertedStatus;
        if (status != null) {
          await _scripts.save(RequestScriptsEntity(
            requestId: requestId,
            assertionsJson: ScriptsJsonCodec.encodeAssertions([AssertionEntity(type: AssertionType.statusEquals, expected: '$status')]),
          ));
        }
      });
    } catch (_) {
      try {
        await _environments.delete(environmentId);
      } catch (_) {}
      rethrow;
    }

    final secrets = plan.secretVariables;
    return RecordedCollectionResult(
      collectionId: written.collectionId,
      collectionName: plan.collection.name,
      requests: written.requests,
      folders: written.folders,
      examples: plan.counts.examples,
      environmentId: environmentId,
      environmentName: environmentName,
      notes: [
        ...plan.notes,
        secrets.isEmpty
            ? 'Created the environment "$environmentName" with baseUrl. The collection already has baseUrl, so it works as it is.'
            : 'Created the environment "$environmentName" with baseUrl and ${secrets.length} empty secret variable'
                '${secrets.length == 1 ? '' : 's'} (${secrets.join(', ')}). Select it and fill in the values: no credential was saved.',
      ],
    );
  }

  Future<String> _freeEnvironmentName(String wanted) async {
    final taken = {for (final e in await _environments.watchAll().first) e.name};
    var name = wanted;
    for (var n = 1; taken.contains(name); n++) {
      name = n == 1 ? '$wanted (recorded)' : '$wanted (recorded $n)';
    }
    return name;
  }
}
