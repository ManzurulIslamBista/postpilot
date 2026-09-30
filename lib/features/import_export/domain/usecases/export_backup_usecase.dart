import '../../../../core/usecases/usecase.dart';
import '../entities/backup_export.dart';
import '../services/backup_service.dart';

/// Exports every collection, environment and global variable as one backup
/// file. The file holds secrets in plain text.
final class ExportBackupUseCase implements UseCase<BackupExport, NoParams> {
  final BackupService _backupService;
  const ExportBackupUseCase(this._backupService);

  @override
  Future<BackupExport> call(NoParams params) => _backupService.export();
}
