import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/file_download.dart';
import '../../../../core/utils/safe_file_name.dart';
import '../../domain/entities/api_docs_model.dart';
import '../../domain/services/api_docs_generator.dart';
import '../../domain/usecases/build_api_docs_usecase.dart';

typedef FileSaver = Future<String?> Function({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
});

/// Backs the documentation dialog of one collection: builds the docs once,
/// keeps the Markdown for preview and copy, and saves .md or .html files.
final class CollectionDocsViewModel with ChangeNotifier {
  final BuildApiDocsUseCase _buildDocs;
  final FileSaver _saveFile;

  CollectionDocsViewModel(this._buildDocs, {this._saveFile = downloadFile});

  bool isLoading = false;
  String? error;
  String markdown = '';

  ApiDocsModel? _model;
  bool _disposed = false;

  bool get isReady => _model != null;

  Future<void> load(int collectionId) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final model = await _buildDocs(collectionId);
      _model = model;
      markdown = ApiDocsGenerator.toMarkdown(model);
    } catch (e) {
      error = e is AppException ? e.message : 'Could not build the documentation: $e';
    }
    isLoading = false;
    if (!_disposed) notifyListeners();
  }

  /// Each returns a message for the user: where the file went, or why it did not.
  Future<String> saveMarkdown() => _save('md', 'text/markdown', () => markdown);

  Future<String> saveHtml() => _save('html', 'text/html', () => ApiDocsGenerator.toHtml(_model!));

  Future<String> _save(String extension, String mimeType, String Function() content) async {
    final model = _model;
    if (model == null) return 'There is nothing to save yet';
    try {
      final baseName = sanitizeFileName('${model.name} docs') ?? 'api-docs';
      final path = await _saveFile(
        fileName: '$baseName.$extension',
        bytes: Uint8List.fromList(utf8.encode(content())),
        mimeType: '$mimeType;charset=utf-8',
      );
      return path == null ? 'Download started' : 'Saved to $path';
    } catch (e) {
      return 'Could not save the file: $e';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
