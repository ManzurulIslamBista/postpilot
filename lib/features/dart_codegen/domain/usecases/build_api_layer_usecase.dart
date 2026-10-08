import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../import_export/domain/services/collection_loader.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/entities/response_example_entity.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../services/api_layer_generator.dart';

/// Reads a whole collection (folders, requests, saved examples) and turns it
/// into the specification [ApiLayerGenerator] works from.
final class BuildApiLayerUseCase {
  final CollectionLoader _loader;
  final ResponseExampleRepository _examples;

  const BuildApiLayerUseCase(this._loader, this._examples);

  Future<ApiLayerResult> call(int collectionId, ApiLayerOptions options) async {
    final spec = await specs(collectionId);
    return const ApiLayerGenerator().generate(spec.name, spec.requests, options: options);
  }

  /// The collection as the generators read it: its name and one [ApiSpecRequest] per request, saved examples included.
  Future<({String name, List<ApiSpecRequest> requests})> specs(int collectionId) async {
    final loaded = await _loader.load(collectionId);
    final requests = <ApiSpecRequest>[];
    for (final request in loaded.requests) {
      requests.add(await _spec(request, loaded.folders, loaded.auth));
    }
    return (name: loaded.collection.name, requests: requests);
  }

  Future<ApiSpecRequest> _spec(ApiRequestEntity r, List<FolderEntity> folders, RequestAuth? collectionAuth) async {
    final body = r.body;
    final kind = switch (body.type) {
      BodyType.none => ApiBodyKind.none,
      BodyType.raw => body.rawContentType == RawContentType.json ? ApiBodyKind.json : ApiBodyKind.text,
      BodyType.formData => ApiBodyKind.form,
      BodyType.urlEncoded => ApiBodyKind.urlEncoded,
      BodyType.graphql => ApiBodyKind.graphql,
      // The generated layer has no file upload yet: a binary body is left out rather than sent as text.
      BodyType.binary => ApiBodyKind.none,
    };
    // Auth the request inherits is the collection's. An API key is just a header or a query
    // parameter; a bearer token is the generated interceptor's job; the rest cannot be generated.
    final auth = r.auth.resolveInherited(collectionAuth);
    final apiKey = auth.type == AuthType.apiKey && auth.apiKeyName.isNotEmpty ? (auth.apiKeyName, auth.apiKeyValue) : null;
    final saved = await _examples.watchByRequest(r.id).first;
    return ApiSpecRequest(
      name: r.name,
      method: r.method.label,
      url: r.url,
      query: [
        for (final p in r.queryParams) if (p.enabled && p.key.isNotEmpty) (p.key, p.value),
        if (apiKey != null && auth.apiKeyLocation == ApiKeyLocation.query) apiKey,
      ],
      headers: [
        for (final h in r.headers) if (h.enabled && h.key.isNotEmpty) (h.key, h.value),
        if (apiKey != null && auth.apiKeyLocation == ApiKeyLocation.header) apiKey,
      ],
      unsupportedAuth: switch (auth.type) {
        AuthType.basic || AuthType.digest || AuthType.awsSignatureV4 || AuthType.jwtBearer || AuthType.hmac || AuthType.oauth2 => auth.type.label,
        _ => null,
      },
      bodyKind: kind,
      bodyText: body.type == BodyType.graphql ? body.graphqlQuery : body.rawText,
      exampleResponse: _successBody(saved),
      examples: [for (final e in saved) ApiSpecExample(name: e.name, statusCode: e.statusCode, body: e.body)],
      folders: _folderNames(r.folderId, folders),
    );
  }

  /// The newest successful example's body, if there is one.
  String? _successBody(List<ResponseExampleEntity> examples) {
    for (final e in examples) {
      if (e.isSuccess && e.body.trim().isNotEmpty) return e.body;
    }
    return null;
  }

  List<String> _folderNames(int? folderId, List<FolderEntity> folders) {
    final names = <String>[];
    var current = folderId;
    var guard = 0;
    while (current != null && guard++ < 50) {
      final folder = folders.where((f) => f.id == current).firstOrNull;
      if (folder == null) break;
      names.insert(0, folder.name);
      current = folder.parentFolderId;
    }
    return names;
  }
}
