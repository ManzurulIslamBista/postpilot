import 'package:flutter/foundation.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/import_format.dart';
import '../../domain/entities/import_summary.dart';
import '../../domain/services/import_format_detector.dart';
import '../../domain/usecases/import_any_usecase.dart';

/// Backs [ImportAnyDialog]: detects the pasted format as the text changes and
/// runs the matching importer.
final class ImportAnyViewModel with ChangeNotifier {
  /// Longer texts are detected off the UI isolate, so pasting a multi-MB
  /// export doesn't stall the field.
  static const _detectInlineLimit = 200000;

  final UseCase<ImportSummary, ImportAnyParams> _importAny;
  ImportAnyViewModel(this._importAny);

  ImportFormat detected = ImportFormat.unknown;

  /// A format the user picked by hand; null means "use the detected one".
  ImportFormat? selected;
  bool isImporting = false;
  String? error;

  /// "Clean up (recommended)", offered for a HAR recording only: drop what is not the app's API, merge repeated calls, make
  /// ids and credentials variables. Off imports every call as it was recorded.
  bool cleanHar = true;

  String _text = '';
  int _detectGeneration = 0;
  bool _disposed = false;

  ImportFormat get format => selected ?? detected;
  bool get hasText => _text.trim().isNotEmpty;
  bool get canImport => hasText && !isImporting && format != ImportFormat.unknown;

  void setText(String text) {
    _text = text;
    error = null;
    final generation = ++_detectGeneration;
    if (text.length <= _detectInlineLimit) {
      detected = ImportFormatDetector.detect(text);
      notifyListeners();
      return;
    }
    notifyListeners();
    compute(ImportFormatDetector.detect, text).then((result) {
      if (_disposed || generation != _detectGeneration) return;
      detected = result;
      notifyListeners();
    });
  }

  void setCleanHar(bool value) {
    cleanHar = value;
    notifyListeners();
  }

  void selectFormat(ImportFormat? format) {
    selected = format;
    error = null;
    notifyListeners();
  }

  /// [collectionId] and [folderId] only matter for cURL commands: they are
  /// added there instead of to a new collection. Returns null on failure, with
  /// [error] set.
  Future<ImportSummary?> import({int? collectionId, int? folderId}) async {
    if (isImporting) return null;
    isImporting = true;
    error = null;
    notifyListeners();
    try {
      final summary = await _importAny(ImportAnyParams(
        text: _text,
        format: selected,
        collectionId: collectionId,
        folderId: folderId,
        cleanHar: cleanHar && format == ImportFormat.har,
      ));
      isImporting = false;
      _notify();
      return summary;
    } catch (e) {
      isImporting = false;
      error = describeError(e, selected ?? detected);
      _notify();
      return null;
    }
  }

  static String describeError(Object error, ImportFormat format) {
    final detail = switch (error) {
      ImportException() => error.message,
      FormatException() => 'the text is not valid JSON or YAML (${error.message})',
      _ => _shortMessage(error),
    };
    if (format == ImportFormat.unknown) return 'Could not import: $detail';
    return 'Could not import as ${format.label}: $detail';
  }

  static String _shortMessage(Object error) {
    final message = error.toString();
    return message.length > 140 ? '${message.substring(0, 140)}...' : message;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
