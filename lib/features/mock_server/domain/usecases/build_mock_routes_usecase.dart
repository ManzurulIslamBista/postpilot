import '../../../import_export/domain/services/collection_loader.dart';
import '../../../request_builder/domain/entities/response_example_entity.dart';
import '../../../request_builder/domain/repositories/response_example_repository.dart';
import '../services/mock_routes.dart';

/// Reads a collection and its saved response examples and turns them into the
/// routes a mock server answers. A request's answer is its newest successful
/// example (or, with none, its newest example of any status).
final class BuildMockRoutesUseCase {
  final CollectionLoader _loader;
  final ResponseExampleRepository _examples;

  const BuildMockRoutesUseCase(this._loader, this._examples);

  Future<MockRouteTable> call(int collectionId) async {
    final loaded = await _loader.load(collectionId);
    final sources = <MockSource>[];
    for (final r in loaded.requests) {
      final example = _pick(await _examples.watchByRequest(r.id).first);
      sources.add(MockSource(
        requestName: r.name,
        method: r.method.label,
        url: r.url,
        exampleStatus: example?.statusCode,
        exampleHeaders: example?.headers ?? const {},
        exampleBody: example?.body,
        exampleName: example?.name,
      ));
    }
    return MockRouteTable.from(sources);
  }

  ResponseExampleEntity? _pick(List<ResponseExampleEntity> examples) {
    for (final e in examples) {
      if (e.isSuccess) return e;
    }
    return examples.firstOrNull;
  }
}
