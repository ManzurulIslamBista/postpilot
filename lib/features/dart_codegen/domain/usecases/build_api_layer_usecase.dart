import '../../../../core/enums/body_type.dart';
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../import_export/domain/services/collection_loader.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../services/api_layer_generator.dart';

/// Reads a whole collection (folders, requests, saved examples) and turns it
/// into the specification [ApiLayerGenerator] works from.
final class BuildApiLayerUseCase {
  final CollectionLoader _loader;
  final ResponseExampleRepository _examples;

  const BuildApiLayerUseCase(this._loader, this._examples);

  Future<ApiLayerResult> call(int collectionId, ApiLayerOptions options) async {
    final loaded = await _loader.load(collectionId);
    final requests = <ApiSpecRequest>[];
    for (final request in loaded.requests) {
      requests.add(await _spec(request, loaded.folders));
    }
    return const ApiLayerGenerator().generate(loaded.collection.name, requests, options: options);
  }

  Future<ApiSpecRequest> _spec(ApiRequestEntity r, List<FolderEntity> folders) async {
    final body = r.body;
    final kind = switch (body.type) {
      BodyType.none => ApiBodyKind.none,
      BodyType.raw => body.rawContentType == RawContentType.json ? ApiBodyKind.json : ApiBodyKind.text,
      BodyType.formData => ApiBodyKind.form,
      BodyType.urlEncoded => ApiBodyKind.urlEncoded,
      BodyType.graphql => ApiBodyKind.graphql,
    };
    return ApiSpecRequest(
      name: r.name,
      method: r.method.label,
      url: r.url,
      query: [for (final p in r.queryParams) if (p.enabled && p.key.isNotEmpty) (p.key, p.value)],
      headers: [for (final h in r.headers) if (h.enabled && h.key.isNotEmpty) (h.key, h.value)],
      bodyKind: kind,
      bodyText: body.type == BodyType.graphql ? body.graphqlQuery : body.rawText,
      exampleResponse: await _example(r.id),
      folders: _folderNames(r.folderId, folders),
    );
  }

  /// The newest successful example's body, if there is one.
  Future<String?> _example(int requestId) async {
    final examples = await _examples.watchByRequest(requestId).first;
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
