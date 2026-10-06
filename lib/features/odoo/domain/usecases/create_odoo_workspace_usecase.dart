import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../documentation/domain/entities/entity_kind.dart';
import '../../../documentation/domain/repositories/documentation_repository.dart';
import '../../../environments/domain/entities/environment_entity.dart';
import '../../../environments/domain/repositories/environment_repository.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../entities/odoo_connection.dart';
import '../services/odoo_json2.dart';
import '../services/odoo_jsonrpc.dart';

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

  /// Where a request's description is kept; without it the notes of the ready-made
  /// requests are not saved.
  final DocumentationRepository? _documentation;

  const CreateOdooWorkspaceUseCase(this._environments, this._collections, this._requests, [this._documentation]);

  /// With [OdooProtocol.jsonRpc] (Odoo 18 and older) the environment holds `odooLogin` and `odooPassword` (secret)
  /// instead of the API key, and `odooProtocol`; [apiKey] is then the password.
  Future<int> createEnvironment({
    required String name,
    required String url,
    required String database,
    required String apiKey,
    bool activate = true,
    OdooProtocol protocol = OdooProtocol.json2,
    String login = '',
  }) async {
    final id = await _environments.create(name);
    Future<void> add(String key, String value, {bool secret = false}) => _environments.upsertVariable(
          EnvironmentVariableEntity(id: 0, environmentId: id, key: key, value: value, isSecret: secret, enabled: true),
        );
    await add(OdooVars.url, url);
    await add(OdooVars.database, database);
    if (protocol == OdooProtocol.jsonRpc) {
      await add(OdooVars.protocol, protocol.id);
      await add(OdooVars.login, login);
      await add(OdooVars.password, apiKey, secret: true);
    } else {
      await add(OdooVars.apiKey, apiKey, secret: true);
    }
    if (activate) await _environments.setActive(id);
    return id;
  }

  /// A collection named [name] with one folder per model, each holding the
  /// standard requests for that model: JSON-2 ones, or with [OdooProtocol.jsonRpc] the `call_kw` ones of Odoo 18 and
  /// older, plus a "Log in" request at the top that opens the session they use. [fieldsByModel] gives the
  /// `fields` used in the examples.
  Future<OdooWorkspaceResult> createCollection({
    required String name,
    required List<String> models,
    Map<String, List<String>> fieldsByModel = const {},
    OdooProtocol protocol = OdooProtocol.json2,
  }) async {
    final collectionId = await _collections.createCollection(name);
    var count = 0;
    Future<int?> save(OdooRequestDraft draft, {int? folderId}) async {
      final id = await _requests.createRequest(collectionId: collectionId, folderId: folderId, name: draft.name);
      final created = await _requests.findById(id);
      if (created == null) return null;
      await _requests.saveRequest(created.copyWith(
        method: HttpMethod.post,
        url: draft.url,
        headers: [for (final e in draft.headers.entries) KeyValueItem(key: e.key, value: e.value)],
        body: RequestBody(type: BodyType.raw, rawContentType: RawContentType.json, rawText: draft.bodyText),
      ));
      // The note says what a request returns and, for write and delete, that the record
      // id is left for the user to set.
      if (draft.note != null) await _documentation?.setMarkdown(EntityKind.request, id, draft.note!);
      return id;
    }

    if (protocol == OdooProtocol.jsonRpc && await save(OdooJsonRpc.loginDraft()) != null) count++;
    for (final model in models) {
      final folderId = await _collections.createFolder(collectionId: collectionId, name: model);
      final sample = fieldsByModel[model] ?? const ['display_name'];
      final drafts = protocol == OdooProtocol.jsonRpc
          ? OdooJsonRpc.templatesFor(model, sampleFields: sample)
          : OdooJson2.templatesFor(model, sampleFields: sample);
      for (final draft in drafts) {
        if (await save(draft, folderId: folderId) != null) count++;
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
      if (draft.note != null) await _documentation?.setMarkdown(EntityKind.request, id, draft.note!);
    }
    return id;
  }
}
