import 'package:flutter/foundation.dart';
import '../../../../core/database/app_database.dart';
import '../../../import_export/domain/services/backup_codec.dart';
import '../../../import_export/domain/services/backup_service.dart';
import '../../../shell/presentation/shell_view_model.dart';
import '../../domain/entities/workplace_content.dart';
import '../../domain/entities/workplace_entity.dart';
import '../../domain/repositories/workplace_repository.dart';
import '../services/native_mac_picker.dart';

final class WorkplaceViewModel with ChangeNotifier {
  final WorkplaceRepository repository;
  final BackupService backupService;
  final AppDatabase database;
  final ShellViewModel shellViewModel;

  WorkplaceViewModel({
    required this.repository,
    required this.backupService,
    required this.database,
    required this.shellViewModel,
  });

  List<WorkplaceEntity> _workplaces = [];
  WorkplaceEntity? _activeWorkplace;
  bool _isBusy = false;
  String? _errorMessage;
  String? _statusMessage;

  List<WorkplaceEntity> get workplaces => _workplaces;
  WorkplaceEntity? get activeWorkplace => _activeWorkplace;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;

  Future<void> init() async {
    _isBusy = true;
    notifyListeners();
    try {
      _workplaces = await repository.getWorkplaces();
      _activeWorkplace = await repository.getActiveWorkplace();

      if (_activeWorkplace != null) {
        await _loadActiveWorkplaceContent(_activeWorkplace!);
      }
    } catch (e) {
      _errorMessage = 'Failed to initialize workplaces: $e';
      debugPrint(_errorMessage);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _loadActiveWorkplaceContent(WorkplaceEntity workplace) async {
    try {
      final content = await repository.loadWorkplaceContent(workplace);
      final jsonStr = content.toJsonString();

      // If the workplace JSON has collections or environments, restore them
      if (content.snapshot.collections.isNotEmpty ||
          content.snapshot.environments.isNotEmpty ||
          content.snapshot.globals.isNotEmpty) {
        await database.clearWorkplaceData();
        await backupService.restore(jsonStr);
      }
    } catch (e) {
      debugPrint('Notice loading workplace content: $e');
    }
  }

  Future<void> switchWorkplace(WorkplaceEntity targetWorkplace) async {
    if (_activeWorkplace?.id == targetWorkplace.id) return;

    _isBusy = true;
    _statusMessage = 'Switching to ${targetWorkplace.name}…';
    notifyListeners();

    try {
      // 1. Save current active workplace to its single workspace.json file
      if (_activeWorkplace != null) {
        await saveCurrentWorkplace();
      }

      // 2. Clear current editor tabs and in-memory/cache DB
      shellViewModel.closeRequest();
      await database.clearWorkplaceData();

      // 3. Set active workplace in repository
      await repository.setActiveWorkplace(targetWorkplace.id);
      _activeWorkplace = targetWorkplace;

      // 4. Load the target workplace's single workspace.json file
      await _loadActiveWorkplaceContent(targetWorkplace);

      _statusMessage = null;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to switch workplace: $e';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<WorkplaceEntity> createWorkplace({
    required String name,
    required String folderPath,
    String? gitRepoUrl,
    String? gitBranch,
    String? gitToken,
  }) async {
    _isBusy = true;
    _statusMessage = 'Creating workplace…';
    notifyListeners();

    try {
      // Save current workplace before switching
      if (_activeWorkplace != null) {
        await saveCurrentWorkplace();
      }

      final workplace = await repository.createWorkplace(
        name: name,
        folderPath: folderPath,
        gitRepoUrl: gitRepoUrl,
        gitBranch: gitBranch,
        gitToken: gitToken,
      );

      _workplaces = await repository.getWorkplaces();

      // Switch to the newly created workplace
      shellViewModel.closeRequest();
      await database.clearWorkplaceData();
      _activeWorkplace = workplace;
      await _loadActiveWorkplaceContent(workplace);

      _statusMessage = null;
      _errorMessage = null;
      return workplace;
    } catch (e) {
      _errorMessage = 'Failed to create workplace: $e';
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> saveCurrentWorkplace() async {
    if (_activeWorkplace == null) return;
    try {
      final exportData = await backupService.export();
      final snapshot = BackupCodec.decode(exportData.text);
      final content = WorkplaceContent(workplace: _activeWorkplace!, snapshot: snapshot);
      await repository.saveWorkplaceContent(_activeWorkplace!, content);
    } catch (e) {
      debugPrint('Notice saving workplace: $e');
    }
  }

  Future<void> syncWithGit({String? commitMessage}) async {
    if (_activeWorkplace == null) return;
    _isBusy = true;
    _statusMessage = 'Syncing with Git repository…';
    _errorMessage = null;
    notifyListeners();

    try {
      await saveCurrentWorkplace();
      await repository.syncWithGit(_activeWorkplace!, commitMessage: commitMessage);
      _workplaces = await repository.getWorkplaces();
      _activeWorkplace = await repository.getActiveWorkplace();
      _statusMessage = 'Synced with Git successfully!';
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Git sync failed: ${_cleanError(e)}';
      _statusMessage = null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> pullFromGit() async {
    if (_activeWorkplace == null) return;
    _isBusy = true;
    _statusMessage = 'Pulling from Git repository…';
    _errorMessage = null;
    notifyListeners();

    try {
      final content = await repository.pullFromGit(_activeWorkplace!);
      await database.clearWorkplaceData();
      await backupService.restore(content.toJsonString());
      _workplaces = await repository.getWorkplaces();
      _activeWorkplace = await repository.getActiveWorkplace();
      _statusMessage = 'Pulled updates from Git!';
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Git pull failed: ${_cleanError(e)}';
      _statusMessage = null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  String _cleanError(dynamic error) {
    var msg = error.toString();
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring('Exception: '.length);
    }
    return msg;
  }

  Future<void> updateWorkplace(WorkplaceEntity updated) async {
    await repository.updateWorkplace(updated);
    _workplaces = await repository.getWorkplaces();
    if (_activeWorkplace?.id == updated.id) {
      _activeWorkplace = updated;
    }
    notifyListeners();
  }

  Future<void> deleteWorkplace(String id) async {
    await repository.deleteWorkplace(id);
    _workplaces = await repository.getWorkplaces();
    if (_activeWorkplace?.id == id) {
      _activeWorkplace = _workplaces.isNotEmpty ? _workplaces.first : null;
      if (_activeWorkplace != null) {
        await switchWorkplace(_activeWorkplace!);
      } else {
        await database.clearWorkplaceData();
      }
    }
    notifyListeners();
  }

  Future<void> revealInFinder() async {
    if (_activeWorkplace == null) return;
    await NativeMacPicker.revealInFinder(_activeWorkplace!.folderPath);
  }

  Future<String> getDefaultWorkplacesDirectory({String? workplaceName}) =>
      repository.getDefaultWorkplacesDirectory(workplaceName: workplaceName);

  Future<String?> pickFolder({String? initialPath}) =>
      repository.pickFolder(initialPath: initialPath);
}
