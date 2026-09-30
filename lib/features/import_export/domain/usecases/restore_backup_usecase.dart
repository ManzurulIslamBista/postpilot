import '../../../../core/usecases/usecase.dart';
import '../entities/import_summary.dart';
import '../services/backup_service.dart';

/// Adds the collections, environments and global variables of a backup file
/// as new data; nothing existing is overwritten (see [BackupService]).
final class RestoreBackupUseCase implements UseCase<ImportSummary, String> {
  final BackupService _backupService;
  const RestoreBackupUseCase(this._backupService);

  @override
  Future<ImportSummary> call(String json) => _backupService.restore(json);
}
