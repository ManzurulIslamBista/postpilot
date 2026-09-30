import 'package:flutter/foundation.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/collection_export_result.dart';

enum CollectionExportKind {
  openApi('Export as OpenAPI', 'openapi', 'json', 'application/json'),
  curlScript('Export cURL script', 'curl', 'txt', 'text/plain');

  final String title;
  final String fileSuffix;

  /// `.sh` would be the natural extension for the script, but downloads refuse
  /// extensions that run code when opened from a file manager.
  final String fileExtension;
  final String mimeType;

  const CollectionExportKind(this.title, this.fileSuffix, this.fileExtension, this.mimeType);
}

/// Backs [ExportCollectionDialog]: renders one collection as OpenAPI or as a
/// cURL script.
final class ExportCollectionViewModel with ChangeNotifier {
  final UseCase<CollectionExportResult, int> _exportOpenApi;
  final UseCase<CollectionExportResult, int> _exportCurlScript;

  ExportCollectionViewModel(this._exportOpenApi, this._exportCurlScript);

  bool isExporting = false;
  String? error;
  CollectionExportResult? result;
  bool _disposed = false;

  Future<void> export(CollectionExportKind kind, int collectionId) async {
    isExporting = true;
    error = null;
    result = null;
    notifyListeners();
    try {
      final useCase = switch (kind) {
        CollectionExportKind.openApi => _exportOpenApi,
        CollectionExportKind.curlScript => _exportCurlScript,
      };
      result = await useCase(collectionId);
    } catch (e) {
      error = _shortMessage(e);
    }
    isExporting = false;
    if (!_disposed) notifyListeners();
  }

  static String _shortMessage(Object e) {
    final message = e.toString();
    return message.length > 140 ? '${message.substring(0, 140)}...' : message;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
