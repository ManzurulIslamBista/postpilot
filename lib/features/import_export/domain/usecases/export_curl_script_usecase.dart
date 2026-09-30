import '../../../../core/usecases/usecase.dart';
import '../../../request_builder/domain/services/code_generators/curl_generator.dart';
import '../../../request_builder/domain/usecases/generate_code_snippet_usecase.dart';
import '../entities/collection_export_result.dart';
import '../services/collection_loader.dart';
import '../services/collection_tree.dart';
import '../services/curl_script_writer.dart';

/// Renders every request of one local collection as a `curl` command in one
/// shell script. Each command comes from [GenerateCodeSnippetUseCase] and
/// [CurlGenerator], so variables, the active environment and inherited
/// collection auth are resolved exactly as when the request is sent.
final class ExportCurlScriptUseCase implements UseCase<CollectionExportResult, int> {
  static const _generator = CurlGenerator();

  final CollectionLoader _loader;
  final UseCase<String, GenerateCodeSnippetParams> _generateSnippet;

  const ExportCurlScriptUseCase(this._loader, this._generateSnippet);

  @override
  Future<CollectionExportResult> call(int collectionId) async {
    final loaded = await _loader.load(collectionId);
    final entries = <CurlScriptEntry>[];
    var failed = 0;
    for (final (:folder, :request) in CollectionTree.ordered(loaded.folders, loaded.requests)) {
      try {
        final command = await _generateSnippet(GenerateCodeSnippetParams(request, _generator));
        entries.add(CurlScriptEntry.generated(name: request.name, folder: folder, command: command));
      } catch (e) {
        // One request with, say, an invalid JWT payload must not sink the whole script.
        failed++;
        entries.add(CurlScriptEntry.failed(name: request.name, folder: folder, failure: '$e'));
      }
    }
    return CollectionExportResult(
      collectionName: loaded.collection.name,
      text: CurlScriptWriter.write(collectionName: loaded.collection.name, entries: entries),
      itemCount: entries.length - failed,
      skipped: failed,
    );
  }
}
