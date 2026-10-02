import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/workplace_exception.dart';
import 'desktop_folder_dialogs.dart';
import 'workplace_storage.dart';

/// Real files and folders: the registry lives in the app-support directory and
/// each workplace keeps a `workspace.json` in its own folder.
///
/// Both directories can be injected so tests never touch the user's real ones.
final class FileWorkplaceStorage implements WorkplaceStorage {
  static const registryFileName = 'workplaces_registry.json';
  static const workspaceFileName = 'workspace.json';

  final Directory? _registryDirectory;
  final String? _defaultWorkplacesDirectory;

  FileWorkplaceStorage({this._registryDirectory, this._defaultWorkplacesDirectory});

  File? _registryFile;

  @override
  bool get usesRealFolders => true;

  @override
  bool get canPickFolder => DesktopFolderDialogs.isSupported;

  @override
  bool get canRevealFolder => DesktopFolderDialogs.isSupported;

  @override
  String get fileManagerName => DesktopFolderDialogs.fileManagerName;

  @override
  Future<String?> readRegistry() async {
    final file = await _registry();
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> writeRegistry(String json) async {
    final file = await _registry();
    await _writeAtomically(file, json);
  }

  @override
  Future<String?> readWorkspace(String folderPath) async {
    final file = File(p.join(folderPath, workspaceFileName));
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> writeWorkspace(String folderPath, String json) async {
    try {
      await Directory(folderPath).create(recursive: true);
      await _writeAtomically(File(p.join(folderPath, workspaceFileName)), json);
    } on FileSystemException catch (e) {
      final reason = e.osError?.message.trim();
      throw WorkplaceException(
        'Could not write to "$folderPath"${reason == null || reason.isEmpty ? '' : ': $reason'}. '
        'Check that the path is valid and you have permission to write there.',
      );
    }
  }

  @override
  Future<String> defaultWorkplacesDirectory() async {
    final configured = _defaultWorkplacesDirectory;
    if (configured != null) return configured;
    try {
      final documents = await getApplicationDocumentsDirectory();
      return p.join(documents.path, 'PostPilot', 'Workplaces');
    } catch (_) {
      return p.join(_homeDirectory(), 'Documents', 'PostPilot', 'Workplaces');
    }
  }

  @override
  String? validateFolderPath(String folderPath) {
    final path = folderPath.trim();
    if (path.isEmpty) return 'Enter or choose a folder for this workplace.';
    if (!p.isAbsolute(path)) {
      final example = Platform.isWindows ? r'C:\Users\you\Documents\PostPilot\Workplaces\Team' : '/home/you/PostPilot/Team';
      return 'Enter the full folder path, for example $example.';
    }
    if (Platform.isWindows) {
      // A drive colon is only legal as the second character ("C:\...").
      final rest = path.length > 2 && path[1] == ':' ? path.substring(2) : path;
      if (RegExp(r'[<>:"|?*]').hasMatch(rest)) {
        return 'The folder path contains characters Windows does not allow (< > : " | ? *).';
      }
    }
    return null;
  }

  @override
  Future<String?> pickFolder({String? initialPath}) => DesktopFolderDialogs.pickFolder(initialPath: initialPath);

  @override
  Future<void> revealFolder(String folderPath) => DesktopFolderDialogs.reveal(folderPath);

  Future<File> _registry() async {
    final cached = _registryFile;
    if (cached != null) return cached;
    final directory = _registryDirectory ?? await _supportDirectory();
    await directory.create(recursive: true);
    return _registryFile = File(p.join(directory.path, registryFileName));
  }

  Future<Directory> _supportDirectory() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return Directory(p.join(_homeDirectory(), '.postpilot'));
    }
  }

  String _homeDirectory() {
    final env = Platform.environment;
    return env['HOME'] ?? env['USERPROFILE'] ?? '.';
  }

  /// Writes beside the target and renames over it, so a crash or full disk
  /// mid-write leaves the previous file intact instead of a truncated one.
  /// Falls back to a direct write where the rename is refused (a sync client
  /// such as OneDrive can briefly hold the target open).
  Future<void> _writeAtomically(File target, String content) async {
    // Re-created on every write: the folder may have been removed since it was last used.
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(content, flush: true);
    try {
      await temp.rename(target.path);
    } on FileSystemException {
      await target.writeAsString(content, flush: true);
      try {
        await temp.delete();
      } on FileSystemException {
        // A stray .tmp is harmless; the next write replaces it.
      }
    }
  }
}
