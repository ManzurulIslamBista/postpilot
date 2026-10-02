import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../domain/entities/workplace_content.dart';
import '../../domain/entities/workplace_entity.dart';
import '../../domain/entities/workplace_exception.dart';
import '../../domain/repositories/workplace_repository.dart';
import '../storage/workplace_storage.dart';
import '../storage/workplace_storage_factory.dart';

/// The repository holds no file-system code of its own: all reads and writes go
/// through a [WorkplaceStorage], real files on desktop/mobile and browser
/// storage on the web. Tests pass a storage pointed at a temp directory.
final class WorkplaceRepositoryImpl implements WorkplaceRepository {
  final Dio _dio;
  final WorkplaceStorage _storage;

  WorkplaceRepositoryImpl({Dio? dio, WorkplaceStorage? storage})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ),
          ),
      _storage = storage ?? createPlatformWorkplaceStorage();

  static const _remoteFileName = 'workspace.json';

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

  Future<({String? activeId, List<WorkplaceEntity> workplaces})> _readRegistry() async {
    final text = await _storage.readRegistry();
    if (text == null) return (activeId: null, workplaces: <WorkplaceEntity>[]);
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      final list = map['workplaces'] as List? ?? [];
      return (
        activeId: map['activeId'] as String?,
        workplaces: [for (final item in list) WorkplaceEntity.fromJson(item as Map<String, dynamic>)],
      );
    } catch (e) {
      debugPrint('Error reading workplaces registry: $e');
      return (activeId: null, workplaces: <WorkplaceEntity>[]);
    }
  }

  Future<void> _saveRegistry(List<WorkplaceEntity> workplaces, {String? activeId}) async {
    final data = {
      'activeId': activeId ?? (await _readRegistry()).activeId,
      'workplaces': workplaces.map((w) => w.toJson()).toList(),
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

    try {
      final content = await _pullFromRemoteGit(workplace);
      await _storage.writeWorkspace(workplace.folderPath, content.toJsonString());
    } on _RemoteWorkspaceMissing {
      final empty = WorkplaceContent.empty(workplace).toJsonString();
      await _storage.writeWorkspace(workplace.folderPath, empty);
      await _pushToRemoteGit(workplace, empty, message: 'Initial commit from PostPilot');
    }
    return workplace.copyWith(lastSyncedAt: DateTime.now());
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
    return _parseContent(text, workplace);
  }

  @override
  Future<void> saveWorkplaceContent(WorkplaceEntity workplace, WorkplaceContent content) async {
    await _storage.writeWorkspace(workplace.folderPath, content.toJsonString());
    await updateWorkplace(workplace.copyWith(updatedAt: DateTime.now()));
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
  Future<void> syncWithGit(WorkplaceEntity workplace, {String? commitMessage}) async {
    if (!workplace.isGitConnected || workplace.gitToken == null) {
      throw const WorkplaceException('This workplace is not connected to a Git repository or has no token.');
    }
    final content = await loadWorkplaceContent(workplace);
    await _pushToRemoteGit(
      workplace,
      content.toJsonString(),
      message: commitMessage ?? 'Update workplace data from PostPilot',
    );
    await updateWorkplace(workplace.copyWith(lastSyncedAt: DateTime.now()));
  }

  @override
  Future<WorkplaceContent> pullFromGit(WorkplaceEntity workplace) async {
    if (!workplace.isGitConnected || workplace.gitToken == null) {
      throw const WorkplaceException('This workplace is not connected to a Git repository or has no token.');
    }
    final content = await _pullFromRemoteGit(workplace);
    await _storage.writeWorkspace(workplace.folderPath, content.toJsonString());
    await updateWorkplace(workplace.copyWith(lastSyncedAt: DateTime.now()));
    return content;
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

  Future<WorkplaceContent> _pullFromRemoteGit(WorkplaceEntity workplace) async {
    final repoInfo = _parseRepo(workplace.gitRepoUrl!);
    final branch = workplace.gitBranch;
    final token = workplace.gitToken!;
    final path =
        'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}/contents/$_remoteFileName?ref=${Uri.encodeQueryComponent(branch)}';

    try {
      final res = await _dio.get(path, options: Options(headers: _authHeaders(token)));

      if (res.statusCode == 200 && res.data is Map) {
        final encoding = res.data['encoding'] as String?;
        final contentRaw = res.data['content'] as String;
        final jsonStr = encoding == 'base64'
            ? utf8.decode(base64Decode(contentRaw.replaceAll(RegExp(r'\s'), '')))
            : contentRaw;
        return _parseContent(jsonStr, workplace);
      }
      throw const WorkplaceException('Unexpected response format from GitHub.');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw _RemoteWorkspaceMissing(
          'No remote "$_remoteFileName" found on branch "$branch" in repository "${repoInfo.owner}/${repoInfo.repo}". Sync (push) first to create it.',
        );
      }
      throw _formatGitDioError(e, repoInfo: repoInfo, branch: branch, operation: 'pulling from Git');
    }
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

  Future<void> _pushToRemoteGit(WorkplaceEntity workplace, String jsonContent, {required String message}) async {
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
        throw _formatGitDioError(e, repoInfo: repoInfo, branch: branch, operation: 'fetching remote file');
      }
    }

    Future<void> put(String? sha) => _dio.put(
      url,
      data: {'message': message, 'content': base64Encode(utf8.encode(jsonContent)), 'branch': branch, 'sha': ?sha},
      options: Options(headers: headers),
    );

    final sha = await currentSha();
    try {
      await put(sha);
    } on DioException catch (e) {
      // 409 Conflict: the remote file changed since we read its SHA; retry once with the latest.
      if (e.response?.statusCode == 409) {
        final latest = await currentSha();
        if (latest != null && latest != sha) {
          try {
            await put(latest);
            return;
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
      return WorkplaceException(
        'GitHub Access Denied: Token lacks permission for repository "${repoInfo.owner}/${repoInfo.repo}". Ensure your token has "repo" scope.',
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
