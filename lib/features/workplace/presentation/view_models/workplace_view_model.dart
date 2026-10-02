import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/database/app_database.dart';
import '../../../import_export/domain/services/backup_service.dart';
import '../../../shell/presentation/shell_view_model.dart';
import '../../domain/entities/workplace_content.dart';
import '../../domain/entities/workplace_entity.dart';
import '../../domain/entities/workplace_exception.dart';
import '../../domain/repositories/workplace_repository.dart';

/// Owns which workplace is open and keeps its `workspace.json` in step with the
/// database.
///
/// The database is the live copy; the file is its mirror. Three rules keep the
/// two from destroying each other:
///  * the database is only replaced after the new workplace's file has been
///    read and parsed, and the old workplace was saved first, so a failure at
///    any step leaves everything as it was;
///  * every change to workplace data is mirrored to the file (debounced), so
///    reloading the file at startup never brings back stale data;
///  * the mirror is paused while the database is being swapped, otherwise the
///    half-emptied database would be written over the file being loaded.
final class WorkplaceViewModel with ChangeNotifier {
  final WorkplaceRepository repository;
  final BackupService backupService;
  final AppDatabase database;
  final ShellViewModel shellViewModel;

  /// How long data must sit unchanged before it is written to the file.
  final Duration autosaveDelay;

  /// How long to wait, after a swap, for the database's own change events to
  /// arrive (and be ignored) before autosave listens again.
  final Duration _settleDelay;

  WorkplaceViewModel({
    required this.repository,
    required this.backupService,
    required this.database,
    required this.shellViewModel,
    this.autosaveDelay = const Duration(milliseconds: 800),
    this._settleDelay = const Duration(milliseconds: 50),
  });

  List<WorkplaceEntity> _workplaces = [];
  WorkplaceEntity? _activeWorkplace;
  bool _isBusy = false;
  String? _errorMessage;
  String? _statusMessage;

  StreamSubscription<void>? _changesSubscription;
  Timer? _autosaveTimer;
  Future<void> _saveChain = Future.value();
  bool _swapping = false;
  bool _autosavePaused = false;
  bool _disposed = false;

  List<WorkplaceEntity> get workplaces => _workplaces;
  WorkplaceEntity? get activeWorkplace => _activeWorkplace;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;

  /// What the current platform can do with workplace folders.
  bool get usesRealFolders => repository.usesRealFolders;
  bool get canBrowseFolders => repository.canPickFolder;
  bool get canRevealFolder => repository.canRevealFolder;
  String get fileManagerName => repository.fileManagerName;

  Future<void> init() async {
    _isBusy = true;
    notifyListeners();
    try {
      _workplaces = await repository.getWorkplaces();
      final active = await repository.getActiveWorkplace();
      if (active != null) {
        final content = await repository.loadWorkplaceContent(active);
        // An empty file next to a populated database means data that predates
        // workplaces: adopt it instead of wiping it.
        if (!_isEmpty(content)) await _withAutosaveHeld(() => _replaceDatabase(content));
      }
      _activeWorkplace = active;
      _errorMessage = null;
      _startAutosave();
    } catch (e) {
      // Autosave stays off and no workplace is marked active: saving the
      // database over a file that could not be read would destroy it.
      _activeWorkplace = null;
      _errorMessage = 'Failed to initialize workplaces: ${_cleanError(e)}';
      debugPrint(_errorMessage);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> switchWorkplace(WorkplaceEntity target) async {
    if (_isBusy || _activeWorkplace?.id == target.id) return;
    await _runBlocking('Switching to ${target.name}…', 'Failed to switch workplace', () async {
      await _persistActive();
      await _activate(target, recoverTo: _activeWorkplace);
    });
  }

  Future<WorkplaceEntity> createWorkplace({
    required String name,
    required String folderPath,
    String? gitRepoUrl,
    String? gitBranch,
    String? gitToken,
  }) async {
    WorkplaceEntity? created;
    await _runBlocking('Creating workplace…', 'Failed to create workplace', () async {
      final previous = _activeWorkplace;
      await _persistActive();
      final workplace = await repository.createWorkplace(
        name: name,
        folderPath: folderPath,
        gitRepoUrl: gitRepoUrl,
        gitBranch: gitBranch,
        gitToken: gitToken,
      );
      try {
        await _activate(workplace, recoverTo: previous);
      } catch (_) {
        // The registry already names the new workplace as active; undo that so
        // it keeps pointing at the workplace whose data is in the database.
        await repository.deleteWorkplace(workplace.id);
        if (previous != null) await repository.setActiveWorkplace(previous.id);
        rethrow;
      }
      created = workplace;
    }, rethrowErrors: true);
    return created!;
  }

  Future<void> deleteWorkplace(String id) async {
    if (_isBusy) return;
    await _runBlocking('Deleting workplace…', 'Failed to delete workplace', () async {
      final deleted = _activeWorkplace?.id == id ? _activeWorkplace : null;
      // Its files stay on disk, so leave them up to date.
      if (deleted != null) await _persistActive();
      await repository.deleteWorkplace(id);
      _workplaces = await repository.getWorkplaces();
      if (deleted != null) await _activate(_workplaces.first, recoverTo: deleted);
    });
  }

  Future<void> updateWorkplace(WorkplaceEntity updated) async {
    await repository.updateWorkplace(updated);
    _workplaces = await repository.getWorkplaces();
    if (_activeWorkplace?.id == updated.id) {
      _activeWorkplace = updated;
    }
    notifyListeners();
  }

  /// Writes the open workplace's data to its file now. Never throws: callers
  /// use it as a courtesy save after an edit, and autosave retries anyway.
  Future<void> saveCurrentWorkplace() async {
    if (_activeWorkplace == null) return;
    try {
      await _persistActive();
    } catch (e) {
      debugPrint('Notice saving workplace: $e');
    }
  }

  Future<void> syncWithGit({String? commitMessage}) async {
    if (_activeWorkplace == null) return;
    _begin('Syncing with Git repository…');
    try {
      await _persistActive();
      await repository.syncWithGit(_activeWorkplace!, commitMessage: commitMessage);
      _workplaces = await repository.getWorkplaces();
      _activeWorkplace = await repository.getActiveWorkplace();
      _statusMessage = 'Synced with Git successfully!';
    } catch (e) {
      _errorMessage = 'Git sync failed: ${_cleanError(e)}';
      _statusMessage = null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> pullFromGit() async {
    final active = _activeWorkplace;
    if (active == null) return;
    _begin('Pulling from Git repository…');
    _swapping = true;
    _autosaveTimer?.cancel();
    try {
      // A network or auth failure ends here with the database untouched.
      final content = await repository.pullFromGit(active);
      try {
        await _replaceDatabase(content);
      } catch (_) {
        // The file now holds the pulled content, so it is what to restore.
        await _recover(active);
        rethrow;
      }
      _workplaces = await repository.getWorkplaces();
      _activeWorkplace = await repository.getActiveWorkplace();
      _statusMessage = 'Pulled updates from Git!';
    } catch (e) {
      _errorMessage = 'Git pull failed: ${_cleanError(e)}';
      _statusMessage = null;
    } finally {
      await Future<void>.delayed(_settleDelay);
      _swapping = false;
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> revealWorkplaceFolder() async {
    final active = _activeWorkplace;
    if (active == null) return;
    await repository.revealFolder(active.folderPath);
  }

  Future<String> getDefaultWorkplacesDirectory({String? workplaceName}) =>
      repository.getDefaultWorkplacesDirectory(workplaceName: workplaceName);

  Future<String?> pickFolder({String? initialPath}) => repository.pickFolder(initialPath: initialPath);

  @override
  void dispose() {
    _disposed = true;
    _autosaveTimer?.cancel();
    _changesSubscription?.cancel();
    super.dispose();
  }

  // --- Swapping the database between workplaces ---------------------------

  /// Makes [target] the open workplace: loads its file, then replaces the
  /// database with it. The file is read and parsed before the database is
  /// touched, so a damaged file aborts with nothing changed. If replacing
  /// still fails halfway, [recoverTo]'s (already saved) data is put back.
  Future<void> _activate(WorkplaceEntity target, {WorkplaceEntity? recoverTo}) async {
    final content = await repository.loadWorkplaceContent(target);
    try {
      await _replaceDatabase(content);
    } catch (e) {
      await _recover(recoverTo);
      rethrow;
    }
    await repository.setActiveWorkplace(target.id);
    _workplaces = await repository.getWorkplaces();
    _activeWorkplace = target;
    _startAutosave();
  }

  Future<void> _recover(WorkplaceEntity? previous) async {
    if (previous == null) return;
    try {
      await _replaceDatabase(await repository.loadWorkplaceContent(previous));
    } catch (e) {
      // The database is in an unknown state; keep it away from the files,
      // which still hold the last good copy of every workplace.
      _autosavePaused = true;
      throw WorkplaceException(
        'The workplace could not be restored after an error ($e). Autosave is off for this session; '
        'your data is safe in the workplace folders. Restart PostPilot.',
      );
    }
  }

  Future<void> _replaceDatabase(WorkplaceContent content) async {
    await database.clearWorkplaceData();
    if (!_isEmpty(content)) await backupService.restore(content.toJsonString());
    shellViewModel.closeRequest();
  }

  bool _isEmpty(WorkplaceContent content) {
    final snapshot = content.snapshot;
    return snapshot.collections.isEmpty && snapshot.environments.isEmpty && snapshot.globals.isEmpty;
  }

  /// [body] with autosave held back and the UI marked busy. Errors become
  /// [errorMessage] (and are rethrown when [rethrowErrors] is set).
  Future<void> _runBlocking(
    String status,
    String failurePrefix,
    Future<void> Function() body, {
    bool rethrowErrors = false,
  }) async {
    _begin(status);
    _swapping = true;
    _autosaveTimer?.cancel();
    try {
      await body();
      _statusMessage = null;
      _errorMessage = null;
    } catch (e) {
      _statusMessage = null;
      _errorMessage = '$failurePrefix: ${_cleanError(e)}';
      if (rethrowErrors) rethrow;
    } finally {
      // Let the change events caused by the swap arrive while they are still ignored.
      await Future<void>.delayed(_settleDelay);
      _swapping = false;
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _withAutosaveHeld(Future<void> Function() body) async {
    _swapping = true;
    try {
      await body();
    } finally {
      await Future<void>.delayed(_settleDelay);
      _swapping = false;
    }
  }

  void _begin(String status) {
    _isBusy = true;
    _statusMessage = status;
    _errorMessage = null;
    notifyListeners();
  }

  // --- Mirroring the database to the file ---------------------------------

  void _startAutosave() {
    _changesSubscription ??= database.workplaceDataChanges().listen((_) => _scheduleAutosave());
  }

  void _scheduleAutosave() {
    if (_disposed || _swapping || _autosavePaused || _activeWorkplace == null) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(autosaveDelay, () {
      if (_disposed || _swapping || _autosavePaused) return;
      unawaited(saveCurrentWorkplace());
    });
  }

  /// Saves one at a time, in order: two overlapping writes of the same file
  /// could land out of order and leave the older data on disk.
  Future<void> _persistActive() {
    final next = _saveChain.catchError((Object _) {}).then((_) => _writeActive());
    _saveChain = next;
    return next;
  }

  Future<void> _writeActive() async {
    final workplace = _activeWorkplace;
    if (workplace == null || _autosavePaused) return;
    final snapshot = await backupService.snapshot();
    await repository.saveWorkplaceContent(workplace, WorkplaceContent(workplace: workplace, snapshot: snapshot));
  }

  String _cleanError(Object error) {
    var msg = error.toString();
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring('Exception: '.length);
    }
    return msg;
  }
}
