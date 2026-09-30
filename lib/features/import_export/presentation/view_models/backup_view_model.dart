import 'package:flutter/foundation.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/backup_export.dart';
import '../../domain/entities/import_summary.dart';

/// Backs [BackupDialog]: builds the backup file and restores one.
final class BackupViewModel with ChangeNotifier {
  final UseCase<BackupExport, NoParams> _exportBackup;
  final UseCase<ImportSummary, String> _restoreBackup;

  BackupViewModel(this._exportBackup, this._restoreBackup);

  bool isExporting = false;
  String? exportError;
  BackupExport? backup;

  bool isRestoring = false;
  String? restoreError;
  bool _disposed = false;

  Future<void> loadBackup() async {
    isExporting = true;
    exportError = null;
    notifyListeners();
    try {
      backup = await _exportBackup(const NoParams());
    } catch (e) {
      exportError = _shortMessage(e);
    }
    isExporting = false;
    _notify();
  }

  /// Returns null on failure, with [restoreError] set.
  Future<ImportSummary?> restore(String text) async {
    if (isRestoring) return null;
    isRestoring = true;
    restoreError = null;
    notifyListeners();
    try {
      final summary = await _restoreBackup(text);
      isRestoring = false;
      _notify();
      return summary;
    } catch (e) {
      isRestoring = false;
      restoreError = 'Could not restore this backup: ${e is ImportException ? e.message : _shortMessage(e)}';
      _notify();
      return null;
    }
  }

  static String _shortMessage(Object e) {
    final message = e.toString();
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
