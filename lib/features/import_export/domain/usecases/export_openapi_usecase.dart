import '../../../../core/usecases/usecase.dart';
import '../entities/collection_export_result.dart';
import '../services/collection_loader.dart';
import '../services/openapi_exporter.dart';

/// Serializes one local collection as an OpenAPI 3.0 JSON document.
final class ExportOpenApiUseCase implements UseCase<CollectionExportResult, int> {
  final CollectionLoader _loader;
  const ExportOpenApiUseCase(this._loader);

  @override
  Future<CollectionExportResult> call(int collectionId) async {
    final loaded = await _loader.load(collectionId);
    final export = OpenApiExporter.export(
      collectionName: loaded.collection.name,
      folders: loaded.folders,
      requests: loaded.requests,
      variables: loaded.variables,
      collectionAuth: loaded.auth,
      defaults: loaded.defaultsTree,
    );
    return CollectionExportResult(
      collectionName: loaded.collection.name,
      text: export.text,
      itemCount: export.operations,
      skipped: export.skipped,
    );
  }
}
