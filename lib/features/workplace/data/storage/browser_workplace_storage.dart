import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/workplace_exception.dart';
import 'workplace_storage.dart';

/// Keeps the registry and every workplace's `workspace.json` in the browser's
/// local storage, for the web build, which cannot touch the file system.
///
/// Browsers allow roughly 5 MB per origin, so an unusually large workspace is
/// refused with a message instead of being silently dropped.
final class BrowserWorkplaceStorage implements WorkplaceStorage {
  static const _registryKey = 'postpilot.workplaces.registry';
  static const _filePrefix = 'postpilot.workplaces.file:';
  static const _secretsPrefix = 'postpilot.workplaces.secrets:';
  static const _maxBytes = 4 * 1024 * 1024;

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
  Future<String?> readWorkspace(String folderPath) async => (await _prefs).getString(_fileKey(folderPath));

  @override
  Future<void> writeWorkspace(String folderPath, String json) => _write(_fileKey(folderPath), json);

  @override
  Future<String?> readLocalSecrets(String folderPath) async => (await _prefs).getString(_secretsKey(folderPath));

  @override
  Future<void> writeLocalSecrets(String folderPath, String json) async {
    try {
      await _write(_secretsKey(folderPath), json);
    } on WorkplaceException {
      // Secrets are optional extras; a full browser store must not stop the workspace from saving.
    }
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

  String _secretsKey(String folderPath) => '$_secretsPrefix${p.normalize(folderPath.trim()).toLowerCase()}';

  /// Case-insensitive, like the desktop file systems the same workspace may later move to.
  String _fileKey(String folderPath) => '$_filePrefix${p.normalize(folderPath.trim()).toLowerCase()}';

  Future<void> _write(String key, String json) async {
    if (json.length > _maxBytes) {
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
}
