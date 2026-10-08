import '../../../../core/errors/app_exception.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../collections/domain/repositories/collection_repository.dart';
import '../../../request_builder/domain/repositories/request_repository.dart';
import '../entities/import_format.dart';
import '../entities/import_summary.dart';
import '../services/import_format_detector.dart';
import 'import_curl_script_usecase.dart';
import 'import_har_usecase.dart';
import 'summarizing_importer.dart';

final class ImportAnyParams {
  final String text;

  /// Skips detection and forces this importer.
  final ImportFormat? format;

  /// Where cURL commands go; other formats always create their own collections.
  /// Null puts cURL commands in a new collection too.
  final int? collectionId;
  final int? folderId;

  /// "Clean up (recommended)" for a HAR recording: only the HAR importer reads it. Off imports every call exactly as recorded.
  final bool cleanHar;

  const ImportAnyParams({required this.text, this.format, this.collectionId, this.folderId, this.cleanHar = false});
}

/// The one import entry point: detects what was pasted (see
/// [ImportFormatDetector]) and hands it to the importer for that format.
final class ImportAnyUseCase implements UseCase<ImportSummary, ImportAnyParams> {
  final UseCase<int, String> _importPostman;
  final UseCase<int, String> _importOpenApi;
  final UseCase<ImportSummary, String> _importInsomnia;
  final UseCase<ImportSummary, String> _importHar;
  final UseCase<ImportSummary, ImportCurlScriptParams> _importCurl;
  final UseCase<ImportSummary, String> _restoreBackup;
  final UseCase<ImportSummary, String> _importPostmanEnvironment;
  final CollectionRepository _collectionRepository;
  final RequestRepository _requestRepository;

  const ImportAnyUseCase(
    this._importPostman,
    this._importOpenApi,
    this._importInsomnia,
    this._importHar,
    this._importCurl,
    this._restoreBackup,
    this._collectionRepository,
    this._requestRepository, {
    required UseCase<ImportSummary, String> importPostmanEnvironment,
    // A named parameter cannot start with an underscore, so it cannot be an initializing formal.
    // ignore: prefer_initializing_formals
  }) : _importPostmanEnvironment = importPostmanEnvironment;

  @override
  Future<ImportSummary> call(ImportAnyParams params) async {
    final format = params.format ?? ImportFormatDetector.detect(params.text);
    final text = params.text;
    switch (format) {
      case ImportFormat.postman:
        return _importCollection(format, _importPostman, text);
      case ImportFormat.postmanEnvironment:
        return _importPostmanEnvironment(text);
      case ImportFormat.openApi:
        return _importCollection(format, _importOpenApi, text);
      case ImportFormat.insomnia:
        return _importInsomnia(text);
      case ImportFormat.har:
        if (_importHar case final CleanableHarImporter cleaner when params.cleanHar) return cleaner.importCleaned(text);
        return _importHar(text);
      case ImportFormat.backup:
        return _restoreBackup(text);
      case ImportFormat.curl:
        return _importCurl(ImportCurlScriptParams(script: text, collectionId: params.collectionId, folderId: params.folderId));
      case ImportFormat.unknown:
        throw const ImportException(
          "this doesn't look like a Postman collection or environment, Insomnia export, HAR file, OpenAPI/Swagger document, cURL command or PostPilot backup.",
        );
    }
  }

  /// An importer that can describe its own result (what it skipped, what it
  /// changed) is asked to; the others only return the new collection's id, so
  /// its name and counts are read back for the success message.
  Future<ImportSummary> _importCollection(ImportFormat format, UseCase<int, String> importer, String text) async {
    if (importer case final SummarizingImporter summarizing) return summarizing.importWithSummary(text);
    return _describeCollection(format, await importer(text));
  }

  Future<ImportSummary> _describeCollection(ImportFormat format, int collectionId) async {
    final collections = await _collectionRepository.watchCollections().first;
    final folders = await _collectionRepository.watchFolders(collectionId).first;
    final requests = await _requestRepository.watchByCollection(collectionId).first;
    return ImportSummary(
      format: format,
      collectionIds: [collectionId],
      collectionName: collections.where((c) => c.id == collectionId).map((c) => c.name).firstOrNull,
      folders: folders.length,
      requests: requests.length,
    );
  }
}
