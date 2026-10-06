import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../collections/domain/repositories/collection_variable_repository.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/request_scripts_entity.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../../../request_builder/domain/repositories/request_scripts_repository.dart';
import '../../../request_flow/domain/entities/flow_settings.dart';
import '../../../scripting/data/models/scripts_json_codec.dart';
import '../../../settings/domain/entities/request_settings.dart';
import '../../../settings/domain/repositories/request_settings_repository.dart';
import '../openapi/generated_case.dart';

/// What a generation wrote.
final class GeneratedTestsResult {
  /// The folder that holds the requests (`Tests`, or `Tests 2` when the collection already had one).
  final String folderName;
  final int created;

  /// How many of them change data and so wait for [GenerateOpenApiTestsUseCase.gateVariable].
  final int gated;

  /// Collection variables that were added: `baseUrl` when the collection had none, and the gate.
  final List<String> variablesAdded;

  const GeneratedTestsResult({required this.folderName, required this.created, required this.gated, required this.variablesAdded});
}

/// Writes the requests of a [GeneratedSelection] into a collection: a `Tests` folder with one sub-folder per
/// category, each request with its assertions.
///
/// A request that changes data (POST, PUT, PATCH, DELETE) is written with a "Run if" condition: it runs only while
/// the variable [gateVariable] is `true`, so a run of the collection does not change a real server by accident.
/// The variable is added to the collection as `false`; setting it to `true` (in the collection or an environment) is
/// the opt-in. The production lock still asks before any of them goes to production.
final class GenerateOpenApiTestsUseCase {
  static const gateVariable = 'allowDataChanging';
  static const defaultFolderName = 'Tests';

  final CollectionRepository _collections;
  final RequestRepository _requests;
  final RequestScriptsRepository _scripts;
  final RequestSettingsRepository _settings;
  final CollectionVariableRepository _variables;

  const GenerateOpenApiTestsUseCase(this._collections, this._requests, this._scripts, this._settings, this._variables);

  Future<GeneratedTestsResult> call(int collectionId, GeneratedSuite suite, GeneratedSelection selection) async {
    final folders = await _collections.watchFolders(collectionId).first;
    final taken = {for (final f in folders) if (f.parentFolderId == null) f.name};
    var folderName = defaultFolderName;
    for (var n = 2; taken.contains(folderName); n++) {
      folderName = '$defaultFolderName $n';
    }

    final createdRequests = <int>[];
    final createdFolders = <int>[];
    var gated = 0;
    try {
      final root = await _collections.createFolder(collectionId: collectionId, name: folderName);
      createdFolders.add(root);
      for (final category in TestCategory.values) {
        final inCategory = [for (final c in selection.cases) if (c.category == category) c];
        if (inCategory.isEmpty) continue;
        final folderId = await _collections.createFolder(collectionId: collectionId, parentFolderId: root, name: category.label);
        createdFolders.add(folderId);
        for (final c in inCategory) {
          final id = await _requests.createRequest(collectionId: collectionId, folderId: folderId, name: c.name);
          createdRequests.add(id);
          await _requests.saveRequest(ApiRequestEntity(
            id: id,
            collectionId: collectionId,
            folderId: folderId,
            name: c.name,
            method: c.method,
            url: c.url,
            headers: c.headers,
            queryParams: c.queryParams,
            body: c.body,
            auth: c.auth,
          ));
          await _scripts.save(RequestScriptsEntity(requestId: id, assertionsJson: ScriptsJsonCodec.encodeAssertions(c.assertions)));
          if (c.changesData) {
            gated++;
            await _settings.save(id, RequestSettings(flow: FlowSettings(runIf: _gate)));
          }
        }
      }
      final added = await _ensureVariables(collectionId, suite, needsGate: gated > 0);
      return GeneratedTestsResult(folderName: folderName, created: createdRequests.length, gated: gated, variablesAdded: added);
    } catch (_) {
      // Half a suite in the sidebar would be run by mistake, and a retry would double it.
      for (final id in createdRequests.reversed) {
        try {
          await _requests.deleteRequest(id);
        } catch (_) {}
      }
      for (final id in createdFolders.reversed) {
        try {
          await _collections.deleteFolder(id);
        } catch (_) {}
      }
      rethrow;
    }
  }

  static RunIfPolicy get _gate => RunIfPolicy(
        enabled: true,
        conditions: [RunCondition(kind: RunConditionKind.variableEquals, name: gateVariable, value: 'true')],
      );

  Future<List<String>> _ensureVariables(int collectionId, GeneratedSuite suite, {required bool needsGate}) async {
    final existing = await _variables.getEnabledMap(collectionId);
    final added = <String>[];
    Future<void> add(String key, String value) async {
      await _variables.upsert(CollectionVariableEntity(id: 0, collectionId: collectionId, key: key, value: value, enabled: true));
      added.add(key);
    }

    if (!existing.containsKey('baseUrl') && suite.baseUrl.isNotEmpty) await add('baseUrl', suite.baseUrl);
    if (needsGate && !existing.containsKey(gateVariable)) await add(gateVariable, 'false');
    return added;
  }
}
