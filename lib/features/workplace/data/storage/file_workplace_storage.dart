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
  static const localSecretsFileName = 'workspace.local.json';
  static const gitIgnoreFileName = '.gitignore';

  /// What the folder's `.gitignore` must list so a `git add .` never takes the secrets.
  static const _ignoredFiles = [localSecretsFileName, '$localSecretsFileName.tmp'];
  static const _ignoreHeading = '# PostPilot: secret values of this workspace, never commit them';

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
  Future<String?> backupRegistry(String json) async {
    try {
      final registry = await _registry();
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp = '${now.year}${two(now.month)}${two(now.day)}T${two(now.hour)}${two(now.minute)}${two(now.second)}';
      // The stamp keeps copies apart; a counter handles two failures in the same second.
      var copy = File('${registry.path}.$stamp.bak');
      for (var i = 2; copy.existsSync(); i++) {
        copy = File('${registry.path}.$stamp-$i.bak');
      }
      await copy.writeAsString(json, flush: true);
      return copy.path;
    } on FileSystemException {
      return null;
    }
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
  Future<String?> readLocalSecrets(String folderPath) async {
    final file = File(p.join(folderPath, localSecretsFileName));
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> writeLocalSecrets(String folderPath, String json) async {
    final file = File(p.join(folderPath, localSecretsFileName));
    try {
      await Directory(folderPath).create(recursive: true);
      await _writeAtomically(file, json);
    } on FileSystemException catch (e) {
      // Not swallowed: with the secrets gone from workspace.json, losing this file loses them.
      final reason = e.osError?.message.trim();
      throw WorkplaceException(
        'Could not write the secrets file $localSecretsFileName in "$folderPath"${reason == null || reason.isEmpty ? '' : ': $reason'}. '
        'Check that the folder is writable and the disk is not full.',
      );
    }
    await _ignoreSecretsInGit(folderPath);
  }

  /// Adds [_ignoredFiles] to the folder's `.gitignore` (created when missing), once:
  /// the lines the user already has are never changed or removed. Best effort: a
  /// `.gitignore` that cannot be written must not stop the workspace from saving.
  Future<void> _ignoreSecretsInGit(String folderPath) async {
    final file = File(p.join(folderPath, gitIgnoreFileName));
    try {
      final existing = await file.exists() ? await file.readAsString() : '';
      final listed = {for (final line in existing.split(RegExp(r'\r?\n'))) line.trim()};
      final missing = [
        for (final name in _ignoredFiles)
          if (!listed.contains(name) && !listed.contains('/$name')) name,
      ];
      if (missing.isEmpty) return;
      final newline = existing.contains('\r\n') ? '\r\n' : '\n';
      final separator = existing.isEmpty || existing.endsWith('\n') ? '' : newline;
      final heading = listed.contains(_ignoreHeading) ? '' : '$_ignoreHeading$newline';
      await file.writeAsString('$existing$separator$heading${missing.join(newline)}$newline', flush: true);
    } on FileSystemException {
      // see above
    }
  }

  @override
  Future<bool> isDirty(String folderPath) async => (await _dirtyMarker(folderPath)).exists();

  @override
  Future<void> setDirty(String folderPath, bool dirty) async {
    final marker = await _dirtyMarker(folderPath);
    try {
      if (dirty) {
        await marker.parent.create(recursive: true);
        await marker.writeAsString(folderPath, flush: true);
      } else if (await marker.exists()) {
        await marker.delete();
      }
    } on FileSystemException catch (e) {
      final reason = e.osError?.message.trim();
      throw WorkplaceException('Could not update the save marker${reason == null || reason.isEmpty ? '' : ': $reason'}.');
    }
  }

  /// One marker file per workplace folder, in the application-support directory (not in the
  /// workplace folder, which a sync client may share with other devices).
  Future<File> _dirtyMarker(String folderPath) async {
    final registry = await _registry();
    // FNV-1a over the normalised path: a stable file name (String.hashCode is not stable between runs).
    var hash = 0x811c9dc5;
    for (final unit in p.normalize(folderPath.trim()).toLowerCase().codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return File(p.join(registry.parent.path, 'unsaved', hash.toRadixString(16).padLeft(8, '0')));
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
