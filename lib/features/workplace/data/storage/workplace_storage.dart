import '../../domain/entities/storage_usage.dart';

/// Where a workplace physically lives, so the repository holds no platform code.
///
/// Desktop and mobile keep a registry file in the app-support directory plus
/// one `workspace.json` per workplace folder. The web build has no file system,
/// so it keeps both in browser storage, where a "folder path" is just a name
/// that keys the stored document.
abstract interface class WorkplaceStorage {
  /// Whether folder paths are real directories on this device.
  bool get usesRealFolders;

  /// Whether [pickFolder] can open a native folder chooser here.
  bool get canPickFolder;

  /// Whether [revealFolder] can open a folder in the system file manager here.
  bool get canRevealFolder;

  /// "Finder", "File Explorer" or "file manager", for labels.
  String get fileManagerName;

  /// The registry document, or null before the first workplace is created.
  Future<String?> readRegistry();
  Future<void> writeRegistry(String json);

  /// Keeps [json], a registry that could not be read, under a timestamped
  /// `.bak` name beside the registry, so repairing or replacing the registry
  /// never destroys it. Returns where the copy is, or null when it could not be made.
  Future<String?> backupRegistry(String json);

  /// The `workspace.json` inside [folderPath], or null when there is none yet.
  Future<String?> readWorkspace(String folderPath);

  /// Creates [folderPath] if needed and writes its `workspace.json`, replacing
  /// any previous one without ever leaving a half-written file behind.
  Future<void> writeWorkspace(String folderPath, String json);

  /// The secrets of the workplace in [folderPath] (`workspace.local.json`), or
  /// null when there are none. They are kept in this file instead of in
  /// `workspace.json`, and nothing pushes it. A failed write throws: the
  /// secrets must never be lost silently. On disk the folder's `.gitignore`
  /// is made to list the file.
  Future<String?> readLocalSecrets(String folderPath);
  Future<void> writeLocalSecrets(String folderPath, String json);

  /// Whether the database holds changes of the workplace in [folderPath] that its
  /// `workspace.json` has not received (a write failed, or the app closed before
  /// it ran). Kept on this device only, outside the workplace folder, so that
  /// the next start does not replace the newer database with the older file.
  Future<bool> isDirty(String folderPath);
  Future<void> setDirty(String folderPath, bool dirty);

  /// The folder new workplaces are suggested under (no name appended).
  Future<String> defaultWorkplacesDirectory();

  /// Why [folderPath] can't be used, or null when it can.
  String? validateFolderPath(String folderPath);

  /// Shows the native folder chooser; null when cancelled or unavailable.
  Future<String?> pickFolder({String? initialPath});

  /// Opens [folderPath] in the system file manager. A no-op where unsupported.
  Future<void> revealFolder(String folderPath);
}

/// A [WorkplaceStorage] whose space is capped, so that it can say how much of it a workspace takes. Only the browser's
/// storage is capped.
abstract interface class CappedWorkplaceStorage {
  /// The size of the `workspace.json` of [folderPath] against the cap; null when there is none yet.
  Future<StorageUsage?> workspaceUsage(String folderPath);
}
