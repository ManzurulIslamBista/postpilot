import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/storage_usage.dart';
import '../../domain/entities/workplace_exception.dart';
import 'workplace_storage.dart';

/// Keeps the registry and every workplace's `workspace.json` in the browser's
/// local storage, for the web build, which cannot touch the file system.
///
/// Browsers allow roughly 5 MB per origin, so an unusually large workspace is
/// refused with a message instead of being silently dropped.
final class BrowserWorkplaceStorage implements WorkplaceStorage, CappedWorkplaceStorage {
  static const _registryKey = 'postpilot.workplaces.registry';
  static const _filePrefix = 'postpilot.workplaces.file:';
  static const _secretsPrefix = 'postpilot.workplaces.secrets:';
  static const _dirtyPrefix = 'postpilot.workplaces.unsaved:';
  static const _registryBackupPrefix = 'postpilot.workplaces.registry.bak:';
  static const _maxBytes = 4 * 1024 * 1024;

  /// The largest `workspace.json` this storage accepts.
  static const maxWorkspaceBytes = _maxBytes;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  bool get usesRealFolders => false;

  @override
  bool get canPickFolder => false;

  @override
  bool get canRevealFolder => false;

  @override
  String get fileManagerName => 'file manager';

  @override
  Future<String?> readRegistry() async => (await _prefs).getString(_registryKey);

  @override
  Future<void> writeRegistry(String json) => _write(_registryKey, json);

  @override
  Future<String?> backupRegistry(String json) async {
    try {
      final key = '$_registryBackupPrefix${DateTime.now().toUtc().toIso8601String()}';
      return await (await _prefs).setString(key, json) ? 'browser storage ($key)' : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> readWorkspace(String folderPath) async => (await _prefs).getString(_fileKey(folderPath));

  @override
  Future<void> writeWorkspace(String folderPath, String json) => _write(_fileKey(folderPath), json);

  @override
  Future<StorageUsage?> workspaceUsage(String folderPath) async {
    final text = (await _prefs).getString(_fileKey(folderPath));
    return text == null ? null : StorageUsage(usedBytes: _storedLength(text), limitBytes: _maxBytes);
  }

  @override
  Future<String?> readLocalSecrets(String folderPath) async => (await _prefs).getString(_secretsKey(folderPath));

  /// Not swallowed when the browser's store is full: with the secrets gone from the workspace, they would be lost.
  @override
  Future<void> writeLocalSecrets(String folderPath, String json) => _write(_secretsKey(folderPath), json);

  @override
  Future<bool> isDirty(String folderPath) async => (await _prefs).getBool(_dirtyKey(folderPath)) ?? false;

  @override
  Future<void> setDirty(String folderPath, bool dirty) async {
    final prefs = await _prefs;
    final ok = dirty ? await prefs.setBool(_dirtyKey(folderPath), true) : await prefs.remove(_dirtyKey(folderPath));
    if (!ok) throw const WorkplaceException('The browser refused to update the save marker (storage may be full or blocked).');
  }

  @override
  Future<String> defaultWorkplacesDirectory() async => p.join('PostPilot', 'Workplaces');

  @override
  String? validateFolderPath(String folderPath) =>
      folderPath.trim().isEmpty ? 'Enter a name for where this workplace is stored.' : null;

  @override
  Future<String?> pickFolder({String? initialPath}) async => null;

  @override
  Future<void> revealFolder(String folderPath) async {}

  String _dirtyKey(String folderPath) => '$_dirtyPrefix${p.normalize(folderPath.trim()).toLowerCase()}';

  String _secretsKey(String folderPath) => '$_secretsPrefix${p.normalize(folderPath.trim()).toLowerCase()}';

  /// Case-insensitive, like the desktop file systems the same workspace may later move to.
  String _fileKey(String folderPath) => '$_filePrefix${p.normalize(folderPath.trim()).toLowerCase()}';

  Future<void> _write(String key, String json) async {
    if (_storedLength(json) > _maxBytes) {
      throw const WorkplaceException(
        'This workspace is too large for browser storage (about 4 MB). '
        'Use the desktop app, which saves it as a file on disk.',
      );
    }
    final saved = await (await _prefs).setString(key, json);
    if (!saved) {
      throw const WorkplaceException('The browser refused to store the workplace (storage may be full or blocked).');
    }
  }

  /// What the browser really stores for [text]: the web `shared_preferences` writes each string JSON-encoded, so every quote and
  /// newline of a workspace takes two characters.
  static int _storedLength(String text) => jsonEncode(text).length;
}
