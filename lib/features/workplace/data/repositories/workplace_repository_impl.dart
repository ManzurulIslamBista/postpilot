import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../domain/entities/workplace_content.dart';
import '../../domain/entities/workplace_entity.dart';
import '../../domain/entities/push_preview.dart';
import '../../domain/entities/workplace_exception.dart';
import '../../domain/repositories/workplace_repository.dart';
import '../../domain/services/secret_splitter.dart';
import '../../domain/services/workspace_diff.dart';
import '../storage/workplace_storage.dart';
import '../storage/workplace_storage_factory.dart';
import '../storage/workplace_token_store.dart';

/// The repository holds no file-system code of its own: all reads and writes go
/// through a [WorkplaceStorage], real files on desktop/mobile and browser
/// storage on the web. Tests pass a storage pointed at a temp directory.
final class WorkplaceRepositoryImpl implements WorkplaceRepository, WorkplaceDirtyTracking {
  final Dio _dio;
  final WorkplaceStorage _storage;
  final WorkplaceTokenStore _tokens;
  final bool Function() _keepSecretsLocal;

  /// What the token store is known to hold per workplace id ('' = no token), so the registry,
  /// which is saved on every autosave, does not rewrite the keychain each time.
  final _knownTokens = <String, String>{};

  /// Where the unreadable registry text last seen was copied to, so one broken file is
  /// copied once per run and not at every read.
  String? _brokenRegistryText;
  String? _brokenRegistryCopy;

  /// [keepSecretsLocal] decides, at every save, whether secret values go to
  /// `workspace.local.json`, beside the workspace and never pushed, instead of `workspace.json`
  /// (which is what Git carries).
  WorkplaceRepositoryImpl({Dio? dio, WorkplaceStorage? storage, WorkplaceTokenStore? tokens, bool Function()? keepSecretsLocal})
    : _keepSecretsLocal = keepSecretsLocal ?? (() => false),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ),
          ),
      _storage = storage ?? createPlatformWorkplaceStorage(),
      _tokens = tokens ?? SecureWorkplaceTokenStore();

  static const _remoteFileName = 'workspace.json';

  @override
  bool get keepsSecretsLocal => _keepSecretsLocal();

  @override
  bool get usesRealFolders => _storage.usesRealFolders;

  @override
  bool get canPickFolder => _storage.canPickFolder;

  @override
  bool get canRevealFolder => _storage.canRevealFolder;

  @override
  String get fileManagerName => _storage.fileManagerName;

  @override
  Future<String> getDefaultWorkplacesDirectory({String? workplaceName}) async {
    final baseDir = await _storage.defaultWorkplacesDirectory();
    if (workplaceName == null || workplaceName.trim().isEmpty) return baseDir;
    final safeName = workplaceName
        .trim()
        // \p{M}: vowel signs and other combining marks (Bengali, Hindi, accents) belong to the letters.
        .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}_\-\s]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), '_');
    return p.join(baseDir, safeName.isEmpty ? 'New_Workplace' : safeName);
  }

  @override
  Future<String?> pickFolder({String? initialPath}) => _storage.pickFolder(initialPath: initialPath);

  @override
  Future<void> revealFolder(String folderPath) => _storage.revealFolder(folderPath);

  // --- Registry -----------------------------------------------------------

  @override
  Future<List<WorkplaceEntity>> getWorkplaces() async {
    final registry = await _readRegistry();
    if (registry.workplaces.isNotEmpty) return registry.workplaces;
    return [await _createInitialDefaultWorkplace()];
  }

  Future<WorkplaceEntity> _createInitialDefaultWorkplace() async {
    final workplace = WorkplaceEntity(
      id: const Uuid().v4(),
      name: 'My Workplace',
      folderPath: await getDefaultWorkplacesDirectory(workplaceName: 'My Workplace'),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    // Created on disk first: a registry entry must never point at a missing file.
    if (await _storage.readWorkspace(workplace.folderPath) == null) {
      await _storage.writeWorkspace(workplace.folderPath, WorkplaceContent.empty(workplace).toJsonString());
    }
    await _saveRegistry([workplace], activeId: workplace.id);
    return workplace;
  }

  /// The registry as saved. A missing or empty file is a first start; a file that cannot be
  /// understood is an error, never an empty list: [getWorkplaces] would answer an empty list
  /// by creating a default workplace and saving over the file, which would drop every workplace
  /// and its Git settings. The damaged file is kept as a timestamped `.bak` and left in place.
  Future<({String? activeId, List<WorkplaceEntity> workplaces})> _readRegistry() async {
    final text = await _storage.readRegistry();
    if (text == null || text.trim().isEmpty) return (activeId: null, workplaces: <WorkplaceEntity>[]);

    final List<WorkplaceEntity> parsed;
    final String? activeId;
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      parsed = [
        for (final item in map['workplaces'] as List? ?? const []) WorkplaceEntity.fromJson(item as Map<String, dynamic>),
      ];
      activeId = map['activeId'] as String?;
    } catch (e) {
      throw await _brokenRegistry(text, e);
    }

    final workplaces = <WorkplaceEntity>[];
    var legacyTokens = false;
    var migrationFailed = false;
    for (var workplace in parsed) {
      final plaintext = workplace.gitToken;
      if (plaintext != null && plaintext.isNotEmpty) {
        // Written by an older version, which kept the token in this file: move it to secure storage.
        try {
          await _tokens.write(workplace.id, plaintext);
          legacyTokens = true;
          _knownTokens[workplace.id] = plaintext;
        } catch (e) {
          // The keychain refused: the token stays in the registry file and the move is tried again next time.
          debugPrint('Could not move the token of "${workplace.name}" to secure storage: $e');
          _knownTokens[workplace.id] = '';
          migrationFailed = true;
        }
      } else {
        if (workplace.isGitConnected) {
          try {
            workplace = workplace.copyWith(gitToken: await _tokens.read(workplace.id));
          } catch (e) {
            debugPrint('Could not read the token of "${workplace.name}" from secure storage: $e');
          }
        }
        _knownTokens[workplace.id] = workplace.gitToken ?? '';
      }
      workplaces.add(workplace);
    }
    if (legacyTokens && !migrationFailed) await _writeRegistry(workplaces, activeId);
    return (activeId: activeId, workplaces: workplaces);
  }

  Future<WorkplaceException> _brokenRegistry(String text, Object error) async {
    if (_brokenRegistryText != text) {
      _brokenRegistryCopy = await _storage.backupRegistry(text);
      _brokenRegistryText = text;
    }
    final copy = _brokenRegistryCopy;
    debugPrint('Error reading the workplaces registry: $error');
    return WorkplaceException(
      'The list of workplaces (workplaces_registry.json) could not be read, so it was left exactly as it is '
      '(${error is FormatException ? error.message : 'damaged content'}). '
      '${copy == null ? 'A backup copy could not be made.' : 'A copy was kept as $copy.'} '
      'Your workspace.json files are untouched. Repair or delete workplaces_registry.json and restart PostPilot.',
    );
  }

  Future<void> _saveRegistry(List<WorkplaceEntity> workplaces, {String? activeId}) async {
    for (final w in workplaces) {
      final token = w.gitToken;
      if (token != null && token.isNotEmpty) {
        if (_knownTokens[w.id] != token) {
          await _tokens.write(w.id, token);
          _knownTokens[w.id] = token;
        }
      } else if (!w.isGitConnected && _knownTokens[w.id] != '') {
        await _tokens.delete(w.id); // disconnected from Git: nothing may keep a token for it
        _knownTokens[w.id] = '';
      }
    }
    await _writeRegistry(workplaces, activeId ?? (await _readRegistry()).activeId);
  }

  /// The registry document: workplaces without their tokens.
  Future<void> _writeRegistry(List<WorkplaceEntity> workplaces, String? activeId) async {
    final data = {
      'activeId': activeId,
      'workplaces': [
        for (final w in workplaces) (w.toJson()..['gitToken'] = null),
      ],
    };
    await _storage.writeRegistry(const JsonEncoder.withIndent('  ').convert(data));
  }

  @override
  Future<WorkplaceEntity?> getActiveWorkplace() async {
    final workplaces = await getWorkplaces();
    final activeId = (await _readRegistry()).activeId;
    return workplaces.firstWhere((w) => w.id == activeId, orElse: () => workplaces.first);
  }

  @override
  Future<void> setActiveWorkplace(String id) async {
    final workplaces = await getWorkplaces();
    await _saveRegistry(workplaces, activeId: id);
  }

  @override
  Future<WorkplaceEntity> createWorkplace({
    required String name,
    required String folderPath,
    String? gitRepoUrl,
    String? gitBranch,
    String? gitToken,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw const WorkplaceException('Enter a name for the workplace.');
    final folder = folderPath.trim();
    final folderError = _storage.validateFolderPath(folder);
    if (folderError != null) throw WorkplaceException(folderError);

    final repoUrl = _blankToNull(gitRepoUrl);
    final token = _blankToNull(gitToken);
    if (repoUrl != null && token == null) {
      throw const WorkplaceException('Enter a GitHub personal access token to connect the repository.');
    }

    final workplaces = await getWorkplaces();
    final clash = workplaces.where((w) => _sameFolder(w.folderPath, folder)).firstOrNull;
    if (clash != null) {
      throw WorkplaceException('The workplace "${clash.name}" already uses this folder. Choose a different folder.');
    }

    if (repoUrl != null) _requireFreeRepository(workplaces, repoUrl, _blankToNull(gitBranch) ?? 'main');

    var workplace = WorkplaceEntity(
      id: const Uuid().v4(),
      name: trimmedName,
      folderPath: folder,
      gitRepoUrl: repoUrl,
      gitBranch: _blankToNull(gitBranch) ?? 'main',
      gitToken: token,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final existing = await _storage.readWorkspace(folder);
    if (existing != null) {
      // Opening a folder that already is a workspace: keep it exactly as it is.
      _parseContent(existing, workplace);
    } else if (workplace.isGitConnected) {
      workplace = await _initFromGit(workplace);
    } else {
      await _storage.writeWorkspace(folder, WorkplaceContent.empty(workplace).toJsonString());
    }

    await _saveRegistry([...workplaces, workplace], activeId: workplace.id);
    return workplace;
  }

  /// A new Git-connected workplace starts from the repository's copy; if the
  /// repository has none yet, from an empty workspace that is pushed as its first commit.
  /// Anything else wrong (bad token, unknown repository, no network) is reported
  /// rather than silently creating a workplace that can never sync.
  Future<WorkplaceEntity> _initFromGit(WorkplaceEntity workplace) async {
    final repoInfo = _parseRepo(workplace.gitRepoUrl!);
    final token = workplace.gitToken!;
    try {
      await _dio.get(
        'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}',
        options: Options(headers: _authHeaders(token)),
      );
    } on DioException catch (e) {
      throw _formatGitDioError(
        e,
        repoInfo: repoInfo,
        branch: workplace.gitBranch,
        operation: 'connecting to the repository',
      );
    }

    String? sha;
    try {
      final pulled = await _pullFromRemoteGit(workplace);
      sha = pulled.sha;
      await _writeWorkspaceFile(workplace.folderPath, pulled.content.toJsonString(), fromRemote: true);
    } on _RemoteWorkspaceMissing {
      final empty = WorkplaceContent.empty(workplace).toJsonString();
      await _storage.writeWorkspace(workplace.folderPath, empty);
      sha = await _pushToRemoteGit(workplace, empty, message: 'Initial commit from PostPilot');
    }
    return workplace.copyWith(lastSyncedAt: DateTime.now(), lastSyncedSha: sha);
  }

  @override
  Future<void> updateWorkplace(WorkplaceEntity workplace) async {
    final registry = await _readRegistry();
    final current = registry.workplaces.where((w) => w.id == workplace.id).firstOrNull;
    // Only when the repository or branch is being changed: a workplace that already
    // shares one (an older registry) must still be able to save its data.
    if (workplace.isGitConnected &&
        (current == null || current.gitRepoUrl != workplace.gitRepoUrl || current.gitBranch != workplace.gitBranch)) {
      _requireFreeRepository(registry.workplaces, workplace.gitRepoUrl!, workplace.gitBranch, exceptId: workplace.id);
    }
    final updated = [
      for (final w in registry.workplaces) w.id == workplace.id ? workplace.copyWith(updatedAt: DateTime.now()) : w,
    ];
    await _saveRegistry(updated);
  }

  @override
  Future<void> deleteWorkplace(String id) async {
    final workplaces = await getWorkplaces();
    final filtered = workplaces.where((w) => w.id != id).toList();
    await _tokens.delete(id);
    _knownTokens.remove(id);
    final activeId = (await _readRegistry()).activeId;
    final newActive = activeId == id ? filtered.firstOrNull?.id : activeId;
    await _saveRegistry(filtered, activeId: newActive);
  }

  // --- workspace.json -----------------------------------------------------

  @override
  Future<WorkplaceContent> loadWorkplaceContent(WorkplaceEntity workplace) async {
    final text = await _storage.readWorkspace(workplace.folderPath);
    if (text == null) {
      final initial = WorkplaceContent.empty(workplace);
      await _storage.writeWorkspace(workplace.folderPath, initial.toJsonString());
      return initial;
    }
    final localText = await _storage.readLocalSecrets(workplace.folderPath);
    final local = SecretSplitter.decodeLocalFile(localText);
    await _keepOrphans(workplace.folderPath, text, local);
    return _parseContent(_mergeLocalSecrets(text, local), workplace);
  }

  @override
  Future<void> saveWorkplaceContent(WorkplaceEntity workplace, WorkplaceContent content) async {
    await _writeWorkspaceFile(workplace.folderPath, content.toJsonString());
    await updateWorkplace(workplace.copyWith(updatedAt: DateTime.now()));
  }

  @override
  Future<bool> hasUnsavedChanges(WorkplaceEntity workplace) => _storage.isDirty(workplace.folderPath);

  @override
  Future<void> setUnsavedChanges(WorkplaceEntity workplace, bool unsaved) =>
      _storage.setDirty(workplace.folderPath, unsaved);

  /// Fills the secrets that `workspace.json` leaves blank from `workspace.local.json`, the ones it
  /// holds for this workspace and the ones that matched nothing the last time.
  String _mergeLocalSecrets(String text, LocalSecrets local) {
    if (local.secrets.isEmpty && local.unmatched.isEmpty) return text;
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      return const JsonEncoder.withIndent('  ').convert(SecretSplitter.merge(map, local.all));
    } catch (_) {
      return text; // Not ours to repair: the caller reports an unreadable file.
    }
  }

  /// Secrets of `workspace.local.json` that belong to nothing in [text] (somebody renamed the
  /// environment or request they were for, in a file changed from outside) are moved to its
  /// `unmatched` part before any save, which would otherwise write only what the workspace has
  /// a place for and lose them. Nothing is removed from `secrets` unless it is kept in `unmatched`.
  Future<void> _keepOrphans(String folder, String text, LocalSecrets local) async {
    if (local.secrets.isEmpty) return;
    final Map<String, dynamic> doc;
    try {
      doc = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final orphans = SecretSplitter.orphans(doc, local.secrets);
    if (orphans.isEmpty) return;
    final secrets = {
      for (final e in local.secrets.entries)
        if (!orphans.containsKey(e.key)) e.key: e.value,
    };
    final unmatched = SecretSplitter.capUnmatched({...local.unmatched, ...orphans});
    try {
      await _storage.writeLocalSecrets(folder, SecretSplitter.encodeLocal(secrets, unmatched: unmatched));
    } on WorkplaceException catch (e) {
      // The entries are still in `secrets`, so nothing is lost; the next successful save moves them.
      debugPrint('Could not set aside the unmatched secrets of "$folder": $e');
    }
  }

  /// Writes the workspace. With "keep secrets local" on, secret values go to
  /// `workspace.local.json` and the shared file holds blanks.
  ///
  /// The secrets file is written first: if the app dies between the two writes, the old
  /// workspace.json is still there with every secret in the local file, never blanks with
  /// the secrets lost. A failed write of either is thrown, not swallowed.
  ///
  /// [fromRemote]: the text came from somebody else (a pull). Its places may not match the secrets
  /// kept here, so the ones it has no place for are kept anyway, as `unmatched`.
  Future<void> _writeWorkspaceFile(String folder, String text, {bool fromRemote = false}) async {
    if (!_keepSecretsLocal()) {
      await _storage.writeWorkspace(folder, text);
      return;
    }
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      await _storage.writeWorkspace(folder, text);
      return;
    }
    final split = SecretSplitter.split(map);
    final previousText = await _storage.readLocalSecrets(folder);
    final local = SecretSplitter.retain(
      doc: split.publicDoc,
      secrets: split.secrets,
      previous: SecretSplitter.decodeLocalFile(previousText),
      keepOrphans: fromRemote,
    );
    // No secrets and nothing to keep: do not create a secrets file (and a .gitignore) for nothing.
    if (previousText != null || local.secrets.isNotEmpty || local.unmatched.isNotEmpty) {
      await _storage.writeLocalSecrets(folder, SecretSplitter.encodeLocal(local.secrets, unmatched: local.unmatched));
    }
    await _storage.writeWorkspace(folder, const JsonEncoder.withIndent('  ').convert(split.publicDoc));
  }

  WorkplaceContent _parseContent(String text, WorkplaceEntity workplace) {
    try {
      return WorkplaceContent.fromJsonString(text, fallbackWorkplace: workplace);
    } catch (e) {
      throw WorkplaceException(
        'The workspace.json in "${workplace.folderPath}" is not a valid PostPilot workspace ($e). '
        'Nothing was changed.',
      );
    }
  }

  // --- Git ----------------------------------------------------------------

  @override
  Future<PushPreview> previewPush(WorkplaceEntity workplace) async {
    if (!workplace.isGitConnected || workplace.gitToken == null) {
      throw const WorkplaceException('This workplace is not connected to a Git repository or has no token.');
    }
    final local = await _storage.readWorkspace(workplace.folderPath);
    final remote = await _fetchRemoteFile(workplace);
    final changes = WorkspaceDiff.compare(remote?.text, local);
    // A workplace that never synced has no sha to compare: the repository's copy counts as someone
    // else's work unless it says the same as this workplace, in which case there is nothing to lose.
    final neverSynced = remote != null && workplace.lastSyncedSha == null && !changes.isEmpty;
    final remoteChanged =
        remote != null && (workplace.lastSyncedSha == null ? !changes.isEmpty : remote.sha != workplace.lastSyncedSha);
    return PushPreview(
      remoteExists: remote != null,
      remoteChanged: remoteChanged,
      neverSynced: neverSynced,
      changes: changes,
      suggestedMessage: changes.commitMessage(),
    );
  }

  @override
  Future<void> syncWithGit(WorkplaceEntity workplace, {String? commitMessage, bool overwrite = false}) async {
    if (!workplace.isGitConnected || workplace.gitToken == null) {
      throw const WorkplaceException('This workplace is not connected to a Git repository or has no token.');
    }
    final content = await loadWorkplaceContent(workplace);
    // The file as saved, not the merged content: with secrets kept local the file is what is safe to share.
    final raw = await _storage.readWorkspace(workplace.folderPath);
    final sha = await _pushToRemoteGit(
      workplace,
      raw ?? content.toJsonString(),
      message: commitMessage ?? 'Update workplace data from PostPilot',
      overwrite: overwrite,
    );
    await updateWorkplace(workplace.copyWith(lastSyncedAt: DateTime.now(), lastSyncedSha: sha ?? workplace.lastSyncedSha));
  }

  @override
  Future<WorkplaceContent> pullFromGit(WorkplaceEntity workplace) async {
    if (!workplace.isGitConnected || workplace.gitToken == null) {
      throw const WorkplaceException('This workplace is not connected to a Git repository or has no token.');
    }
    final pulled = await _pullFromRemoteGit(workplace);
    // The repository's copy has blank secrets; the ones kept in workspace.local.json are put back before it is used.
    final local = SecretSplitter.decodeLocalFile(await _storage.readLocalSecrets(workplace.folderPath));
    final mergedText = _mergeLocalSecrets(pulled.content.toJsonString(), local);
    final merged = _parseContent(mergedText, workplace);
    // fromRemote: the local secrets this workspace has no place for stay in the local file.
    await _writeWorkspaceFile(workplace.folderPath, mergedText, fromRemote: true);
    await updateWorkplace(workplace.copyWith(lastSyncedAt: DateTime.now(), lastSyncedSha: pulled.sha));
    return merged;
  }

  Map<String, String> _authHeaders(String token) => {
    'Authorization': 'token $token',
    'Accept': 'application/vnd.github.v3+json',
  };

  ({String owner, String repo}) _parseRepo(String url) {
    var cleaned = url.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^https?://(www\.)?github\.com/'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^git@github\.com:'), '');
    final parts = cleaned.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (owner: parts[0], repo: parts[1].replaceFirst(RegExp(r'\.git$'), ''));
    }
    throw const WorkplaceException('Invalid GitHub repository. Use "owner/repo" or "https://github.com/owner/repo".');
  }

  static String _repoApi(({String owner, String repo}) repoInfo) => 'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}';

  /// The repository's `workspace.json` text and blob sha, or null when the branch has none yet.
  ///
  /// The Contents API serves files up to 1 MB. For a bigger one it answers 403 ("too large") or
  /// 200 without the content, which must not be mistaken for a permission problem: the file is
  /// then read through the Git Data API, which serves blobs up to 100 MB.
  Future<({String text, String? sha})?> _fetchRemoteFile(WorkplaceEntity workplace) async {
    final repoInfo = _parseRepo(workplace.gitRepoUrl!);
    final branch = workplace.gitBranch;
    final token = workplace.gitToken!;
    final path = '${_repoApi(repoInfo)}/contents/$_remoteFileName?ref=${Uri.encodeQueryComponent(branch)}';

    try {
      try {
        final res = await _dio.get(path, options: Options(headers: _authHeaders(token)));
        final data = res.data;
        if (res.statusCode != 200 || data is! Map) throw const WorkplaceException('Unexpected response format from GitHub.');
        final sha = data['sha'] as String?;
        final content = data['content'];
        if (content is String && content.isNotEmpty) {
          final text = data['encoding'] == 'base64' ? utf8.decode(base64Decode(content.replaceAll(RegExp(r'\s'), ''))) : content;
          return (text: text, sha: sha);
        }
        if (sha == null) throw const WorkplaceException('Unexpected response format from GitHub.');
        return (text: await _fetchBlob(repoInfo, sha, branch, token), sha: sha);
      } on DioException catch (e) {
        if (!_isTooLarge(e)) rethrow;
        final sha = await _shaFromListing(repoInfo, branch, token);
        if (sha == null) rethrow;
        return (text: await _fetchBlob(repoInfo, sha, branch, token), sha: sha);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _formatGitDioError(e, repoInfo: repoInfo, branch: branch, operation: 'pulling from Git');
    }
  }

  /// A file the Contents API refused for its size: GitHub says so with a 403 whose message (and
  /// `too_large` error code) names the Git Data API as the way to read it.
  bool _isTooLarge(DioException e) {
    if (e.response?.statusCode != 403) return false;
    final data = e.response?.data;
    if (data is! Map) return false;
    final errors = data['errors'];
    return '${data['message']}'.toLowerCase().contains('too large') ||
        (errors is List && errors.any((x) => x is Map && x['code'] == 'too_large'));
  }

  /// The text of the blob [sha] through the Git Data API (up to 100 MB).
  Future<String> _fetchBlob(({String owner, String repo}) repoInfo, String sha, String branch, String token) async {
    try {
      final res = await _dio.get('${_repoApi(repoInfo)}/git/blobs/$sha', options: Options(headers: _authHeaders(token)));
      final data = res.data;
      final content = data is Map ? data['content'] : null;
      if (content is! String) throw const WorkplaceException('Unexpected response format from GitHub.');
      return data['encoding'] == 'base64' ? utf8.decode(base64Decode(content.replaceAll(RegExp(r'\s'), ''))) : content;
    } on DioException catch (e) {
      throw _formatGitDioError(e, repoInfo: repoInfo, branch: branch, operation: 'reading $_remoteFileName');
    }
  }

  /// The blob sha of `workspace.json` on [branch], from the listing of the repository's root: the
  /// only place to learn it when the Contents API refuses the file itself for its size.
  Future<String?> _shaFromListing(({String owner, String repo}) repoInfo, String branch, String token) async {
    try {
      final res = await _dio.get(
        '${_repoApi(repoInfo)}/contents?ref=${Uri.encodeQueryComponent(branch)}',
        options: Options(headers: _authHeaders(token)),
      );
      final data = res.data;
      if (data is List) {
        for (final entry in data) {
          if (entry is Map && entry['name'] == _remoteFileName && entry['type'] == 'file') return entry['sha'] as String?;
        }
      }
      return null;
    } on DioException catch (e) {
      throw _formatGitDioError(e, repoInfo: repoInfo, branch: branch, operation: 'listing the repository');
    }
  }

  Future<({WorkplaceContent content, String? sha})> _pullFromRemoteGit(WorkplaceEntity workplace) async {
    final remote = await _fetchRemoteFile(workplace);
    if (remote == null) {
      final repoInfo = _parseRepo(workplace.gitRepoUrl!);
      throw _RemoteWorkspaceMissing(
        'No remote "$_remoteFileName" found on branch "${workplace.gitBranch}" in repository "${repoInfo.owner}/${repoInfo.repo}". Sync (push) first to create it.',
      );
    }
    return (content: _parseContent(remote.text, workplace), sha: remote.sha);
  }

  Future<void> _ensureBranchExists({
    required ({String owner, String repo}) repoInfo,
    required String branch,
    required String token,
  }) async {
    final authHeader = _authHeaders(token);
    final repoUrl = 'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}';

    try {
      await _dio.get('$repoUrl/branches/${Uri.encodeComponent(branch)}', options: Options(headers: authHeader));
      return; // Target branch already exists
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        throw _formatGitDioError(e, repoInfo: repoInfo, branch: branch, operation: 'verifying branch');
      }
    }

    // Branch 404 Not Found: auto-create it from repository's default branch
    try {
      final repoRes = await _dio.get(repoUrl, options: Options(headers: authHeader));
      final defaultBranch = (repoRes.data is Map ? repoRes.data['default_branch'] : null) as String? ?? 'main';

      final refRes = await _dio.get('$repoUrl/git/ref/heads/$defaultBranch', options: Options(headers: authHeader));
      final defaultSha = (refRes.data is Map && refRes.data['object'] is Map)
          ? refRes.data['object']['sha'] as String?
          : null;

      if (defaultSha != null) {
        await _dio.post(
          '$repoUrl/git/refs',
          data: {'ref': 'refs/heads/$branch', 'sha': defaultSha},
          options: Options(headers: authHeader),
        );
        debugPrint('PostPilot: Auto-created remote branch "$branch" from "$defaultBranch"');
      }
    } on DioException catch (e) {
      debugPrint('PostPilot: Branch creation note ($branch): ${e.message}');
    }
  }

  /// Pushes [jsonContent] as `workspace.json` and returns the file's new blob sha.
  ///
  /// Unless [overwrite], a repository whose file differs from the one this
  /// workplace last synced with is refused: someone else pushed meanwhile, and
  /// writing over it would silently throw their work away. A workplace that never
  /// synced (created over an existing folder, or connected to the repository later)
  /// has no sha to compare, so it is refused too unless the repository's copy says
  /// the same as [jsonContent].
  Future<String?> _pushToRemoteGit(
    WorkplaceEntity workplace,
    String jsonContent, {
    required String message,
    bool overwrite = false,
  }) async {
    final repoInfo = _parseRepo(workplace.gitRepoUrl!);
    final branch = workplace.gitBranch;
    final token = workplace.gitToken!;
    final headers = _authHeaders(token);

    await _ensureBranchExists(repoInfo: repoInfo, branch: branch, token: token);

    final url = 'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}/contents/$_remoteFileName';
    final ref = Uri.encodeQueryComponent(branch);

    Future<String?> currentSha() async {
      try {
        final res = await _dio.get('$url?ref=$ref', options: Options(headers: headers));
        return res.data is Map ? res.data['sha'] as String? : null;
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) return null;
        // Over the Contents API's size limit: only the sha is needed, and the listing has it.
        if (_isTooLarge(e)) return _shaFromListing(repoInfo, branch, token);
        throw _formatGitDioError(e, repoInfo: repoInfo, branch: branch, operation: 'fetching remote file');
      }
    }

    Future<String?> put(String? sha) async {
      final res = await _dio.put(
        url,
        data: {'message': message, 'content': base64Encode(utf8.encode(jsonContent)), 'branch': branch, 'sha': ?sha},
        options: Options(headers: headers),
      );
      final content = res.data is Map ? res.data['content'] : null;
      return content is Map ? content['sha'] as String? : null;
    }

    final sha = await currentSha();
    if (!overwrite && sha != null) {
      final known = workplace.lastSyncedSha;
      if (known != null && sha != known) throw const RemoteChangedException();
      if (known == null) {
        final remote = await _fetchRemoteFile(workplace);
        if (remote == null || !WorkspaceDiff.compare(remote.text, jsonContent).isEmpty) {
          throw const RemoteChangedException.neverSynced();
        }
      }
    }
    try {
      return await put(sha);
    } on DioException catch (e) {
      // 409 Conflict: the remote file changed since we read its SHA; retry once with the latest.
      if (e.response?.statusCode == 409) {
        final latest = await currentSha();
        if (latest != null && latest != sha) {
          if (!overwrite) throw const RemoteChangedException();
          try {
            return await put(latest);
          } on DioException catch (retryError) {
            throw _formatGitDioError(
              retryError,
              repoInfo: repoInfo,
              branch: branch,
              operation: 'pushing workplace to Git',
            );
          }
        }
      }
      throw _formatGitDioError(e, repoInfo: repoInfo, branch: branch, operation: 'pushing workplace to Git');
    }
  }

  WorkplaceException _formatGitDioError(
    DioException e, {
    required ({String owner, String repo}) repoInfo,
    required String branch,
    required String operation,
  }) {
    final status = e.response?.statusCode;
    final responseMsg = e.response?.data is Map ? e.response?.data['message'] as String? : null;

    if (status == 401) {
      return const WorkplaceException(
        'GitHub Authentication failed: Personal Access Token (classic) is invalid or expired.',
      );
    }
    if (status == 403) {
      final reason = (responseMsg ?? '').trim();
      final lower = reason.toLowerCase();
      if (lower.contains('rate limit')) {
        return WorkplaceException(
          'GitHub rate limit reached while $operation ($reason). Wait a few minutes and try again.',
        );
      }
      if (lower.contains('too large')) {
        return WorkplaceException(
          'GitHub would not send $_remoteFileName while $operation: $reason Use a smaller workspace or fewer saved responses.',
        );
      }
      return WorkplaceException(
        'GitHub Access Denied while $operation${reason.isEmpty ? '' : ': $reason'}. '
        'Make sure your token can read and write repository "${repoInfo.owner}/${repoInfo.repo}" (the "repo" scope) '
        'and, if the repository belongs to an organization that uses SSO, that the token is authorized for it.',
      );
    }
    if (status == 404) {
      return WorkplaceException(
        'GitHub Not Found: Repository "${repoInfo.owner}/${repoInfo.repo}" or branch "$branch" was not found, or token has insufficient permissions.',
      );
    }
    if (status == 409) {
      if (responseMsg != null &&
          (responseMsg.contains('Secret detected') || responseMsg.contains('Repository rule violations'))) {
        return const WorkplaceException(
          'GitHub Security Block: A secret or token was detected in the payload and blocked by GitHub Push Protection.',
        );
      }
      return const WorkplaceException('GitHub Conflict: Remote file has changed. Pull changes before pushing.');
    }
    if (status == 422) {
      return WorkplaceException('GitHub Validation error: ${responseMsg ?? "Invalid branch or commit state."}');
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const WorkplaceException('Network error: Unable to reach GitHub. Please verify your internet connection.');
    }
    return WorkplaceException('GitHub error ($status) during $operation: ${responseMsg ?? e.message}');
  }

  // --- helpers ------------------------------------------------------------

  /// Two workplaces pushing one `workspace.json` to the same repository and branch
  /// would keep overwriting each other, so a repository + branch belongs to one.
  void _requireFreeRepository(List<WorkplaceEntity> workplaces, String repoUrl, String branch, {String? exceptId}) {
    final wanted = _parseRepo(repoUrl);
    for (final other in workplaces) {
      if (other.id == exceptId || !other.isGitConnected) continue;
      final ({String owner, String repo}) used;
      try {
        used = _parseRepo(other.gitRepoUrl!);
      } on WorkplaceException {
        continue;
      }
      if (used.owner.toLowerCase() == wanted.owner.toLowerCase() &&
          used.repo.toLowerCase() == wanted.repo.toLowerCase() &&
          other.gitBranch == branch) {
        throw WorkplaceException(
          'The workplace "${other.name}" already uses ${used.owner}/${used.repo} on branch "$branch". '
          'Two workplaces sharing one file would overwrite each other; use another branch or repository.',
        );
      }
    }
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  bool _sameFolder(String a, String b) => p.normalize(a.trim()).toLowerCase() == p.normalize(b.trim()).toLowerCase();
}

/// The repository answered, but has no `workspace.json` on the branch yet.
final class _RemoteWorkspaceMissing extends WorkplaceException {
  const _RemoteWorkspaceMissing(super.message);
}
