import 'package:flutter/foundation.dart';
import '../../domain/usecases/export_postman_collection_usecase.dart';
import '../../domain/usecases/import_curl_usecase.dart';
import '../../domain/usecases/import_openapi_usecase.dart';
import '../../domain/usecases/import_postman_collection_usecase.dart';

/// Backs all the import/export dialogs. They're modals — only one is ever
/// open at a time — so one ViewModel with a method per operation is simpler
/// than several near-identical ones; each method resets only its own
/// isLoading/error state.
final class ImportExportViewModel with ChangeNotifier {
  final ImportPostmanCollectionUseCase _importPostmanUseCase;
  final ImportCurlUseCase _importCurlUseCase;
  final ExportPostmanCollectionUseCase _exportPostmanUseCase;
  final ImportOpenApiUseCase _importOpenApiUseCase;

  ImportExportViewModel(
    this._importPostmanUseCase,
    this._importCurlUseCase,
    this._exportPostmanUseCase,
    this._importOpenApiUseCase,
  );

  bool isImportingPostman = false;
  String? importPostmanError;

  bool isImportingCurl = false;
  String? importCurlError;

  bool isImportingOpenApi = false;
  String? importOpenApiError;

  bool isExporting = false;
  String? exportError;
  String? exportedJson;

  /// Returns the new collection's id, or null if the import failed.
  Future<int?> importPostman(String json) async {
    isImportingPostman = true;
    importPostmanError = null;
    notifyListeners();
    try {
      final id = await _importPostmanUseCase(json);
      isImportingPostman = false;
      notifyListeners();
      return id;
    } catch (e) {
      isImportingPostman = false;
      importPostmanError = 'Could not parse this as a Postman collection: ${_shortMessage(e)}';
      notifyListeners();
      return null;
    }
  }

  /// Returns the new request's id, or null if the import failed.
  Future<int?> importCurl(ImportCurlParams params) async {
    isImportingCurl = true;
    importCurlError = null;
    notifyListeners();
    try {
      final id = await _importCurlUseCase(params);
      isImportingCurl = false;
      notifyListeners();
      return id;
    } catch (e) {
      isImportingCurl = false;
      importCurlError = 'Could not parse this as a cURL command: ${_shortMessage(e)}';
      notifyListeners();
      return null;
    }
  }

  /// Returns the new collection's id, or null if the import failed.
  Future<int?> importOpenApi(String text) async {
    isImportingOpenApi = true;
    importOpenApiError = null;
    notifyListeners();
    try {
      final id = await _importOpenApiUseCase(text);
      isImportingOpenApi = false;
      notifyListeners();
      return id;
    } catch (e) {
      isImportingOpenApi = false;
      importOpenApiError = 'Could not parse this as an OpenAPI/Swagger document: ${_shortMessage(e)}';
      notifyListeners();
      return null;
    }
  }

  Future<void> exportPostman(int collectionId) async {
    isExporting = true;
    exportError = null;
    notifyListeners();
    try {
      exportedJson = await _exportPostmanUseCase(collectionId);
    } catch (e) {
      exportError = _shortMessage(e);
    }
    isExporting = false;
    notifyListeners();
  }

  static String _shortMessage(Object e) {
    final message = e.toString();
    return message.length > 140 ? '${message.substring(0, 140)}...' : message;
  }
}
