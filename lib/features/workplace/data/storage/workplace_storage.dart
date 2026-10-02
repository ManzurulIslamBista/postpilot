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

  /// The `workspace.json` inside [folderPath], or null when there is none yet.
  Future<String?> readWorkspace(String folderPath);

  /// Creates [folderPath] if needed and writes its `workspace.json`, replacing
  /// any previous one without ever leaving a half-written file behind.
  Future<void> writeWorkspace(String folderPath, String json);

  /// The folder new workplaces are suggested under (no name appended).
  Future<String> defaultWorkplacesDirectory();

  /// Why [folderPath] can't be used, or null when it can.
  String? validateFolderPath(String folderPath);

  /// Shows the native folder chooser; null when cancelled or unavailable.
  Future<String?> pickFolder({String? initialPath});

  /// Opens [folderPath] in the system file manager. A no-op where unsupported.
  Future<void> revealFolder(String folderPath);
}
