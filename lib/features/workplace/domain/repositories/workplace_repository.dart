import '../entities/push_preview.dart';
import '../entities/storage_usage.dart';
import '../entities/workplace_content.dart';
import '../entities/workplace_entity.dart';

abstract interface class WorkplaceRepository {
  /// Whether secret values are kept in `workspace.local.json`, beside the workspace and never
  /// pushed, instead of in `workspace.json`.
  bool get keepsSecretsLocal;

  /// Whether workplace folders are real directories on this device (false on
  /// the web, where a workplace is stored in the browser).
  bool get usesRealFolders;

  /// Whether [pickFolder] can show a native folder chooser on this platform.
  bool get canPickFolder;

  /// Whether [revealFolder] can open a folder in the system file manager.
  bool get canRevealFolder;

  /// "Finder", "File Explorer" or "file manager", for labels.
  String get fileManagerName;

  /// Returns all registered workplaces.
  Future<List<WorkplaceEntity>> getWorkplaces();

  /// Gets the currently active workplace, or null if none is selected.
  Future<WorkplaceEntity?> getActiveWorkplace();

  /// Sets the active workplace ID.
  Future<void> setActiveWorkplace(String id);

  /// Registers a new workplace and makes it active.
  ///
  /// If the folder already holds a `workspace.json` it is opened as it is, never
  /// overwritten; otherwise an empty one is created (or, for a Git-connected
  /// workplace, the repository's copy is pulled). Throws a `WorkplaceException`
  /// with a displayable message when the folder or repository can't be used.
  Future<WorkplaceEntity> createWorkplace({
    required String name,
    required String folderPath,
    String? gitRepoUrl,
    String? gitBranch,
    String? gitToken,
  });

  /// Updates workplace metadata (such as git settings or folder).
  Future<void> updateWorkplace(WorkplaceEntity workplace);

  /// Removes a workplace from the registry. Its files are left in place.
  Future<void> deleteWorkplace(String id);

  /// Loads the entire single JSON file (`workspace.json`) from the workplace folder.
  Future<WorkplaceContent> loadWorkplaceContent(WorkplaceEntity workplace);

  /// Saves the entire content as the single `workspace.json` file inside the workplace folder.
  Future<void> saveWorkplaceContent(WorkplaceEntity workplace, WorkplaceContent content);

  /// Syncs (pushes or commits) the single JSON file to the connected Git repository
  /// using GitHub REST API and Personal Access Token (classic).
  ///
  /// Refused with `RemoteChangedException` when the repository changed since the last
  /// sync, unless [overwrite].
  Future<void> syncWithGit(WorkplaceEntity workplace, {String? commitMessage, bool overwrite = false});

  /// What a push would do, without doing it: the changes against the repository's copy
  /// and a commit message written from them.
  Future<PushPreview> previewPush(WorkplaceEntity workplace);

  /// Pulls the single JSON file from the connected Git repository and saves it locally.
  Future<WorkplaceContent> pullFromGit(WorkplaceEntity workplace);

  /// Returns the default folder path for a workplace on this device.
  Future<String> getDefaultWorkplacesDirectory({String? workplaceName});

  /// Opens the native folder chooser; null when cancelled or unavailable.
  Future<String?> pickFolder({String? initialPath});

  /// Opens a workplace folder in the system file manager (no-op where unsupported).
  Future<void> revealFolder(String folderPath);
}

/// What a repository can remember about a workplace beyond its data: whether the database holds
/// changes that `workspace.json` has not received yet (a write failed, or the app closed before
/// the autosave ran). Kept apart from [WorkplaceRepository] so that a repository without it, such
/// as a test double, still works; the view model then simply has no marker.
///
/// The marker lives on this device only. At the next start it tells the view model that the
/// database is newer than the file, so the older file must not replace it.
abstract interface class WorkplaceDirtyTracking {
  Future<bool> hasUnsavedChanges(WorkplaceEntity workplace);
  Future<void> setUnsavedChanges(WorkplaceEntity workplace, bool unsaved);
}

/// How full the store behind a workplace is, for a repository whose store has a cap (the browser's). Kept apart from
/// [WorkplaceRepository] like [WorkplaceDirtyTracking]: a repository without it simply has nothing to warn about.
abstract interface class WorkplaceStorageBudget {
  /// The size of [workplace]'s saved file against the cap; null when the store has none (real folders).
  Future<StorageUsage?> storageUsage(WorkplaceEntity workplace);
}
