import '../../../../core/errors/app_exception.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/import_format.dart';
import '../entities/import_summary.dart';
import '../entities/imported_collection.dart';
import '../services/curl_script_parser.dart';
import '../services/imported_collection_writer.dart';

final class ImportCurlScriptParams {
  final String script;

  /// The collection (and optionally folder) to add the requests to. Null
  /// creates a new collection for them.
  final int? collectionId;
  final int? folderId;

  const ImportCurlScriptParams({required this.script, this.collectionId, this.folderId});
}

/// Turns pasted `curl` commands, one or a whole script, into requests.
final class ImportCurlScriptUseCase implements UseCase<ImportSummary, ImportCurlScriptParams> {
  static const newCollectionName = 'Imported cURL';

  final ImportedCollectionWriter _writer;
  const ImportCurlScriptUseCase(this._writer);

  @override
  Future<ImportSummary> call(ImportCurlScriptParams params) async {
    final parsed = CurlScriptParser.parse(params.script);
    if (parsed.requests.isEmpty) throw const ImportException('no cURL command with a URL was found.');

    final targetId = params.collectionId;
    if (targetId != null) {
      await _writer.addItems(targetId, params.folderId, parsed.requests);
      return ImportSummary(
        format: ImportFormat.curl,
        collectionIds: [targetId],
        requests: parsed.requests.length,
        skipped: parsed.skipped,
      );
    }
    final written = await _writer.write(ImportedCollection(newCollectionName, parsed.requests));
    return ImportSummary(
      format: ImportFormat.curl,
      collectionIds: [written.collectionId],
      collectionName: newCollectionName,
      requests: written.requests,
      skipped: parsed.skipped,
    );
  }
}
