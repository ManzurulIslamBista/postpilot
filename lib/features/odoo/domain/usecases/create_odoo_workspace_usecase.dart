import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../services/odoo_json2.dart';

class OdooWorkspaceResult {
  final int? environmentId;
  final int? collectionId;
  final int requestCount;
  const OdooWorkspaceResult({this.environmentId, this.collectionId, this.requestCount = 0});
}

/// Sets Odoo up as a workspace in one step: an environment holding the URL,
/// database and API key (so switching between Odoo servers is switching
/// environment), and a collection with ready-to-send JSON-2 requests for each
/// chosen model.
final class CreateOdooWorkspaceUseCase {
  final EnvironmentRepository _environments;
  final CollectionRepository _collections;
  final RequestRepository _requests;

  const CreateOdooWorkspaceUseCase(this._environments, this._collections, this._requests);

  Future<int> createEnvironment({
    required String name,
    required String url,
    required String database,
    required String apiKey,
    bool activate = true,
  }) async {
    final id = await _environments.create(name);
    Future<void> add(String key, String value, {bool secret = false}) => _environments.upsertVariable(
          EnvironmentVariableEntity(id: 0, environmentId: id, key: key, value: value, isSecret: secret, enabled: true),
        );
    await add(OdooVars.url, url);
    await add(OdooVars.database, database);
    await add(OdooVars.apiKey, apiKey, secret: true);
    if (activate) await _environments.setActive(id);
    return id;
  }

  /// A collection named [name] with one folder per model, each holding the
  /// standard JSON-2 requests for that model. [fieldsByModel] gives the
  /// `fields` used in the examples.
  Future<OdooWorkspaceResult> createCollection({
    required String name,
    required List<String> models,
    Map<String, List<String>> fieldsByModel = const {},
  }) async {
    final collectionId = await _collections.createCollection(name);
    var count = 0;
    for (final model in models) {
      final folderId = await _collections.createFolder(collectionId: collectionId, name: model);
      for (final draft in OdooJson2.templatesFor(model, sampleFields: fieldsByModel[model] ?? const ['display_name'])) {
        final id = await _requests.createRequest(collectionId: collectionId, folderId: folderId, name: draft.name);
        final created = await _requests.findById(id);
        if (created == null) continue;
        await _requests.saveRequest(created.copyWith(
          method: HttpMethod.post,
          url: draft.url,
          headers: [for (final e in draft.headers.entries) KeyValueItem(key: e.key, value: e.value)],
          body: RequestBody(type: BodyType.raw, rawContentType: RawContentType.json, rawText: draft.bodyText),
        ));
        count++;
      }
    }
    return OdooWorkspaceResult(collectionId: collectionId, requestCount: count);
  }

  /// Saves one request (a converted RPC call, say) into [collectionId].
  Future<int> addRequest({required int collectionId, required OdooRequestDraft draft}) async {
    final id = await _requests.createRequest(collectionId: collectionId, name: draft.name);
    final created = await _requests.findById(id);
    if (created != null) {
      await _requests.saveRequest(created.copyWith(
        method: HttpMethod.post,
        url: draft.url,
        headers: [for (final e in draft.headers.entries) KeyValueItem(key: e.key, value: e.value)],
        body: RequestBody(type: BodyType.raw, rawContentType: RawContentType.json, rawText: draft.bodyText),
      ));
    }
    return id;
  }
}
