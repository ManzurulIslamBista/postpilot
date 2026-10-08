import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../../../../core/database/app_database.dart';
import '../../../import_export/domain/services/backup_codec.dart';
import '../../../import_export/domain/services/backup_service.dart';
import '../../../shell/presentation/shell_view_model.dart';
import '../../domain/entities/push_preview.dart';
import '../../domain/entities/storage_usage.dart';
import '../../domain/entities/workplace_content.dart';
import '../../domain/entities/workplace_entity.dart';
import '../../domain/entities/workplace_exception.dart';
import '../../domain/repositories/workplace_repository.dart';
import '../../domain/services/secret_splitter.dart';
import '../../domain/services/credential_keeper.dart';

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
///    half-emptied database would be written over the file being loaded;
///  * a database with changes the file never received (a write failed, or the app
///    closed before the autosave ran) is newer than the file: the repository's
///    marker says so at the next start, and the file is rewritten from the database
///    instead of replacing it.
final class WorkplaceViewModel with ChangeNotifier, WidgetsBindingObserver {
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
  Future<void>? _saveChain;
  bool _swapping = false;
  bool _autosavePaused = false;
  bool _disposed = false;
  bool _observingLifecycle = false;

  /// Why the workspace file could not be written, until a write succeeds again.
  String? _saveError;

  StorageUsage? _storageUsage;

  /// Whether the "database has changes the file may not have" marker is set for the open
  /// workplace, so it is written once per period of changes and not at every change.
  bool _unsaved = false;

  /// Counts the changes seen, so a save can tell whether more arrived while it ran.
  int _changeCount = 0;

  /// Marker writes, in order: a clear must never overtake the set before it. Null while there is none
  /// (a future made ahead of time would be tied to the zone that made it).
  Future<void>? _markerChain;

  List<WorkplaceEntity> get workplaces => _workplaces;
  WorkplaceEntity? get activeWorkplace => _activeWorkplace;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;

  /// "Could not save workspace file: reason" while the last write of the workspace file
  /// failed. The data is safe in the database and the next save retries, but the file (what
  /// Git pushes, and what a restart can rebuild from) is behind, and the user must know.
  String? get saveError => _saveError;

  /// How much of the browser's storage the open workplace's file takes, once it is close to the cap (see
  /// [StorageUsage.isNearLimit]) so the UI can warn before a save is refused; null otherwise, and always on a real folder.
  StorageUsage? get storageWarning => _storageUsage != null && _storageUsage!.isNearLimit ? _storageUsage : null;

  /// What the current platform can do with workplace folders.
  bool get usesRealFolders => repository.usesRealFolders;
  bool get canBrowseFolders => repository.canPickFolder;
  bool get canRevealFolder => repository.canRevealFolder;
  String get fileManagerName => repository.fileManagerName;

  Future<void> init() async {
    _isBusy = true;
    notifyListeners();
    var replaced = false;
    var keptDatabase = false;
    try {
      _workplaces = await repository.getWorkplaces();
      final active = await repository.getActiveWorkplace();
      if (active != null) {
        final content = await repository.loadWorkplaceContent(active);
        final unsaved = await _hasUnsavedChanges(active);
        // A database with changes the file never received is newer than the file: the file
        // must not replace it (that would throw those changes away), it is rewritten instead.
        // Unless the database is empty: then it was lost or reset, and the file is all there is.
        if (unsaved && !await _databaseIsEmpty()) {
          keptDatabase = true;
          _unsaved = true;
        } else if (!_isEmpty(content) && !await _databaseMatches(content)) {
          // An empty file next to a populated database means data that predates
          // workplaces: adopt it instead of wiping it. A file the database already
          // matches (the normal case, autosave keeps them in step) is left alone:
          // reloading it would hand every row a new id and forget which environment
          // was active. Only a file changed from outside (a Git pull, a manual edit)
          // replaces the database.
          await _withAutosaveHeld(() => _replaceDatabase(content, activeEnvironment: active.activeEnvironment));
          replaced = true;
          _unsaved = unsaved;
        } else if (unsaved) {
          _writeMarker(false, workplace: active); // the file already says what the database says
        }
      }
      _activeWorkplace = active;
      _errorMessage = null;
      await _refreshStorageUsage();
      _startAutosave();
      // The restored rows have new ids; write them back so the next start finds
      // the file and the database identical again. The same when the database was
      // kept because it was newer: the file is behind and is rewritten now.
      if (replaced || keptDatabase) await saveCurrentWorkplace();
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
  /// use it as a courtesy save after an edit, and autosave retries anyway. A failure
  /// is not hidden: it becomes [saveError] for the UI to show.
  Future<void> saveCurrentWorkplace() async {
    if (_activeWorkplace == null) return;
    try {
      await _persistActive();
    } catch (e) {
      debugPrint('Notice saving workplace: $e');
    }
  }

  /// What a push to Git would publish in plain text, as "Environment › name" or
  /// "Collection › Request › Authorization header": the secret-marked values of the
  /// workspace when they are not kept in `workspace.local.json`, and in any case every
  /// value left in `workspace.json` that looks like a credential (a token in a header,
  /// a password in a body, a variable named like one but not marked secret).
  Future<List<String>> secretsInWorkspace() async {
    final snapshot = await backupService.snapshot();
    final doc = jsonDecode(BackupCodec.encode(snapshot)) as Map<String, dynamic>;
    return SecretSplitter.exposed(doc, keepLocal: repository.keepsSecretsLocal);
  }

  /// Set when the last push was refused because the repository had changes this
  /// workplace had not pulled; the UI then offers "pull first" or "overwrite".
  bool remoteChanged = false;

  /// What a push would do, for the confirmation dialog. Null (with [errorMessage]) when the repository can't be read.
  Future<PushPreview?> previewPush() async {
    final active = _activeWorkplace;
    if (active == null || _isBusy) return null;
    _begin('Checking the repository…');
    try {
      await _persistActive();
      return await repository.previewPush(active);
    } catch (e) {
      _errorMessage = 'Git check failed: ${_cleanError(e)}';
      _statusMessage = null;
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> syncWithGit({String? commitMessage, bool overwrite = false}) async {
    if (_activeWorkplace == null || _isBusy) return;
    _begin('Syncing with Git repository…');
    remoteChanged = false;
    try {
      await _persistActive();
      await repository.syncWithGit(_activeWorkplace!, commitMessage: commitMessage, overwrite: overwrite);
      _workplaces = await repository.getWorkplaces();
      _activeWorkplace = await repository.getActiveWorkplace();
      _statusMessage = 'Synced with Git successfully!';
    } catch (e) {
      remoteChanged = e is RemoteChangedException;
      _errorMessage = 'Git sync failed: ${_cleanError(e)}';
      _statusMessage = null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> pullFromGit() async {
    final active = _activeWorkplace;
    if (active == null || _isBusy) return;
    _begin('Pulling from Git repository…');
    _swapping = true;
    _autosaveTimer?.cancel();
    try {
      // A network or auth failure ends here with the database untouched.
      final content = await repository.pullFromGit(active);
      // The repository's copy has credentials blank: what this device already has is kept, never erased.
      final text = await _keepingLocalCredentials(content);
      try {
        await _replaceDatabase(content, restoreText: text, activeEnvironment: active.activeEnvironment);
      } catch (_) {
        // The file now holds the pulled content, so it is what to restore.
        await _recover(active);
        rethrow;
      }
      // The database is what the file says again: nothing is waiting to be saved.
      _unsaved = false;
      _writeMarker(false, workplace: active);
      // The file still holds the repository's blanks where credentials were kept: write what the database has.
      if (text != content.toJsonString()) await _persistActive();
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
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
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
    // The registry knows which environment was active when [target] was last saved; [target] itself may be older.
    final stored = (await repository.getWorkplaces()).where((w) => w.id == target.id).firstOrNull;
    try {
      await _replaceDatabase(content, activeEnvironment: stored != null ? stored.activeEnvironment : target.activeEnvironment);
    } catch (e) {
      await _recover(recoverTo);
      rethrow;
    }
    await repository.setActiveWorkplace(target.id);
    _workplaces = await repository.getWorkplaces();
    _activeWorkplace = target;
    // The database now is the file of [target]: nothing is waiting to be saved, and no save of it has failed.
    _saveError = null;
    _unsaved = false;
    _writeMarker(false, workplace: target);
    _storageUsage = null;
    await _refreshStorageUsage();
    _startAutosave();
  }

  Future<void> _recover(WorkplaceEntity? previous) async {
    if (previous == null) return;
    try {
      await _replaceDatabase(
        await repository.loadWorkplaceContent(previous),
        activeEnvironment: previous.activeEnvironment,
      );
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

  /// Makes the database hold [content]. A workspace file does not say which environment was
  /// active, so [activeEnvironment] (the name saved with the workplace) is selected again.
  /// [content]'s text with every credential it has blank filled from the database as it is now.
  Future<String> _keepingLocalCredentials(WorkplaceContent content) async {
    final pulled = content.toJsonString();
    try {
      final current = jsonDecode(BackupCodec.encode(await backupService.snapshot(), includeGit: true)) as Map<String, dynamic>;
      final kept = CredentialKeeper.keep(jsonDecode(pulled) as Map<String, dynamic>, current);
      final text = const JsonEncoder.withIndent('  ').convert(kept);
      return jsonEncode(kept) == jsonEncode(jsonDecode(pulled)) ? pulled : text;
    } catch (_) {
      return pulled; // the safeguard must never stop a pull
    }
  }

  Future<void> _replaceDatabase(WorkplaceContent content, {String? activeEnvironment, String? restoreText}) async {
    await database.clearWorkplaceData();
    if (!_isEmpty(content)) await backupService.restore(restoreText ?? content.toJsonString(), restoreGit: true);
    await _selectEnvironment(activeEnvironment);
    shellViewModel.closeRequest();
  }

  /// The name of the environment that is active in the database now, if any. A one-shot query,
  /// not a stream: a stream's first value needs the database's timers, which a fake clock never fires.
  Future<String?> _activeEnvironmentName() async {
    try {
      final active = await (database.select(database.environments)..where((e) => e.isActive.equals(true))).get();
      return active.firstOrNull?.name;
    } catch (_) {
      return null;
    }
  }

  /// Makes the environment called [name] active again, when it still exists. A failure only leaves none active.
  Future<void> _selectEnvironment(String? name) async {
    if (name == null) return;
    try {
      final all = await database.select(database.environments).get();
      final match = all.where((e) => e.name == name).firstOrNull;
      if (match != null) await database.environmentsDao.setActive(match.id);
    } catch (e) {
      debugPrint('Could not select the environment "$name" again: $e');
    }
  }

  /// Whether the database already holds exactly what [content] describes. The
  /// export date is ignored; everything else (including the file-local folder ids
  /// the format uses) must be equal, which it is only if the file was written from
  /// this very database.
  Future<bool> _databaseMatches(WorkplaceContent content) async {
    String fingerprint(BackupSnapshot snapshot) => BackupCodec.encode(
      BackupSnapshot(
        exportedAt: DateTime.utc(2000),
        collections: snapshot.collections,
        environments: snapshot.environments,
        globals: snapshot.globals,
      ),
    );
    try {
      return fingerprint(await backupService.snapshot()) == fingerprint(content.snapshot);
    } catch (_) {
      return false; // When in doubt, load the file: that is the safe direction.
    }
  }

  bool _isEmpty(WorkplaceContent content) => _isEmptySnapshot(content.snapshot);

  bool _isEmptySnapshot(BackupSnapshot snapshot) =>
      snapshot.collections.isEmpty && snapshot.environments.isEmpty && snapshot.globals.isEmpty;

  Future<bool> _databaseIsEmpty() async {
    try {
      return _isEmptySnapshot(await backupService.snapshot());
    } catch (_) {
      return true; // When in doubt, load the file: that is the safe direction.
    }
  }

  // --- The unsaved-changes marker ---------------------------------------------

  WorkplaceDirtyTracking? get _tracker =>
      repository is WorkplaceDirtyTracking ? repository as WorkplaceDirtyTracking : null;

  Future<bool> _hasUnsavedChanges(WorkplaceEntity workplace) async {
    try {
      return await _tracker?.hasUnsavedChanges(workplace) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sets or clears the marker for [workplace] (default: the open one), after the writes before it.
  /// Without the marker only the protection against a lost write is gone, so a failure is not an error.
  void _writeMarker(bool unsaved, {WorkplaceEntity? workplace}) {
    final tracker = _tracker;
    final target = workplace ?? _activeWorkplace;
    if (tracker == null || target == null) return;
    _markerChain = (_markerChain ?? Future<void>.value()).then<void>((_) => tracker.setUnsavedChanges(target, unsaved)).catchError((Object e) {
      debugPrint('Could not update the unsaved-changes marker: $e');
    });
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
    if (!_observingLifecycle) {
      _observingLifecycle = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  /// Autosave waits for the data to sit still; a window about to be closed (or a
  /// browser tab hidden) may never give it the time. Save what is pending now.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final leaving =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached;
    if (!leaving || _disposed || _swapping || _autosavePaused || _activeWorkplace == null) return;
    _autosaveTimer?.cancel();
    unawaited(saveCurrentWorkplace());
  }

  void _scheduleAutosave() {
    if (_disposed || _swapping || _autosavePaused || _activeWorkplace == null) return;
    // Before the debounce: a window closed inside it must still leave the marker behind.
    _changeCount++;
    if (!_unsaved) {
      _unsaved = true;
      _writeMarker(true);
    }
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(autosaveDelay, () {
      if (_disposed || _swapping || _autosavePaused) return;
      unawaited(saveCurrentWorkplace());
    });
  }

  /// Saves one at a time, in order: two overlapping writes of the same file
  /// could land out of order and leave the older data on disk.
  Future<void> _persistActive() {
    final previous = _saveChain;
    final next = (previous == null ? Future<void>.value() : previous.catchError((Object _) {})).then((_) => _writeActive());
    _saveChain = next;
    return next;
  }

  Future<void> _writeActive() async {
    final workplace = _activeWorkplace;
    if (workplace == null || _autosavePaused) return;
    final changesBefore = _changeCount;
    try {
      final snapshot = await backupService.snapshot(includeGit: true);
      // Which environment is active is saved with the workplace (on this device), not in the shared file.
      final environment = await _activeEnvironmentName();
      final tracked = workplace.copyWith(activeEnvironment: environment);
      await repository.saveWorkplaceContent(tracked, WorkplaceContent(workplace: tracked, snapshot: snapshot));
      if (_activeWorkplace?.id == workplace.id) _activeWorkplace = _activeWorkplace!.copyWith(activeEnvironment: environment);
    } catch (e) {
      _saveError = 'Could not save workspace file: ${_cleanError(e)}';
      if (!_disposed) notifyListeners();
      rethrow;
    }
    // The file has everything the database had when the save began; changes that arrived while it
    // ran keep the marker (their own autosave follows).
    if (_unsaved && changesBefore == _changeCount) {
      _unsaved = false;
      _writeMarker(false, workplace: workplace);
    }
    final markers = _markerChain;
    if (markers != null) await markers;
    await _refreshStorageUsage();
    if (_saveError != null) {
      _saveError = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// Measures the open workplace's file where the store has a cap, and tells the UI when the size changed.
  Future<void> _refreshStorageUsage() async {
    final repo = repository;
    final workplace = _activeWorkplace;
    if (repo is! WorkplaceStorageBudget || workplace == null) return;
    StorageUsage? usage;
    try {
      usage = await (repo as WorkplaceStorageBudget).storageUsage(workplace);
    } catch (_) {
      return; // a reading that failed is no reason to alarm anyone; the next save measures again
    }
    if (usage == _storageUsage) return;
    _storageUsage = usage;
    if (!_disposed) notifyListeners();
  }

  String _cleanError(Object error) {
    var msg = error.toString();
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring('Exception: '.length);
    }
    return msg;
  }
}
