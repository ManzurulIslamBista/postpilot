import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/workplace_content.dart';
import '../../domain/entities/workplace_entity.dart';
import '../../domain/repositories/workplace_repository.dart';
import '../../presentation/services/native_mac_picker.dart';

final class WorkplaceRepositoryImpl implements WorkplaceRepository {
  final Dio _dio;
  static const _workplaceFileName = 'workspace.json';
  static const _registryFileName = 'workplaces_registry.json';

  WorkplaceRepositoryImpl({Dio? dio}) : _dio = dio ?? Dio();

  File? _cachedRegistryFile;

  Future<File> _getRegistryFile() async {
    if (_cachedRegistryFile != null) return _cachedRegistryFile!;
    Directory dir;
    try {
      dir = await getApplicationSupportDirectory();
    } catch (_) {
      final home = Platform.environment['HOME'] ?? '.';
      dir = Directory(p.join(home, '.postpilot'));
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File(p.join(dir.path, _registryFileName));
    _cachedRegistryFile = file;
    return file;
  }

  @override
  Future<String> getDefaultWorkplacesDirectory({String? workplaceName}) async {
    String baseDir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      baseDir = p.join(docs.path, 'PostPilot', 'Workplaces');
    } catch (_) {
      final home = Platform.environment['HOME'] ?? '.';
      baseDir = p.join(home, 'Documents', 'PostPilot', 'Workplaces');
    }

    if (workplaceName != null && workplaceName.trim().isNotEmpty) {
      final safeName = workplaceName
          .trim()
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\s]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      return p.join(baseDir, safeName.isEmpty ? 'New_Workplace' : safeName);
    }
    return baseDir;
  }

  @override
  Future<String?> pickFolder({String? initialPath}) => NativeMacPicker.pickFolder(initialPath: initialPath);

  @override
  Future<List<WorkplaceEntity>> getWorkplaces() async {
    final file = await _getRegistryFile();
    if (!file.existsSync()) {
      // First run: create a default workplace if none exists
      final defaultWp = await _createInitialDefaultWorkplace();
      return [defaultWp];
    }
    try {
      final text = await file.readAsString();
      final map = jsonDecode(text) as Map<String, dynamic>;
      final list = map['workplaces'] as List? ?? [];
      final workplaces = list
          .map((item) => WorkplaceEntity.fromJson(item as Map<String, dynamic>))
          .toList();
      if (workplaces.isEmpty) {
        final defaultWp = await _createInitialDefaultWorkplace();
        return [defaultWp];
      }
      return workplaces;
    } catch (e) {
      debugPrint('Error reading workplaces registry: $e');
      final defaultWp = await _createInitialDefaultWorkplace();
      return [defaultWp];
    }
  }

  Future<WorkplaceEntity> _createInitialDefaultWorkplace() async {
    final defaultFolder = await getDefaultWorkplacesDirectory(workplaceName: 'My Workplace');
    final workplace = WorkplaceEntity(
      id: const Uuid().v4(),
      name: 'My Workplace',
      folderPath: defaultFolder,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _saveRegistry([workplace], activeId: workplace.id);

    // Initialize the single workspace.json file
    final dir = Directory(workplace.folderPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final jsonFile = File(p.join(workplace.folderPath, _workplaceFileName));
    if (!jsonFile.existsSync()) {
      final content = WorkplaceContent.empty(workplace);
      await jsonFile.writeAsString(content.toJsonString());
    }
    return workplace;
  }

  Future<void> _saveRegistry(List<WorkplaceEntity> workplaces, {String? activeId}) async {
    final file = await _getRegistryFile();
    final currentActive = activeId ?? await _readActiveId();
    final data = {
      'activeId': currentActive,
      'workplaces': workplaces.map((w) => w.toJson()).toList(),
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  Future<String?> _readActiveId() async {
    final file = await _getRegistryFile();
    if (!file.existsSync()) return null;
    try {
      final text = await file.readAsString();
      final map = jsonDecode(text) as Map<String, dynamic>;
      return map['activeId'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<WorkplaceEntity?> getActiveWorkplace() async {
    final workplaces = await getWorkplaces();
    if (workplaces.isEmpty) return null;
    final activeId = await _readActiveId();
    if (activeId == null) return workplaces.first;
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
    final workplaces = await getWorkplaces();
    final id = const Uuid().v4();
    var workplace = WorkplaceEntity(
      id: id,
      name: name.trim(),
      folderPath: folderPath.trim(),
      gitRepoUrl: gitRepoUrl?.trim().isNotEmpty == true ? gitRepoUrl!.trim() : null,
      gitBranch: gitBranch?.trim().isNotEmpty == true ? gitBranch!.trim() : 'main',
      gitToken: gitToken?.trim().isNotEmpty == true ? gitToken!.trim() : null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 1. Ensure folder exists on PC
    final dir = Directory(workplace.folderPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // 2. Check if git repo connection is requested
    final jsonFile = File(p.join(workplace.folderPath, _workplaceFileName));
    WorkplaceContent initialContent;

    if (workplace.isGitConnected && workplace.gitToken != null) {
      try {
        // Try pulling remote workspace.json if it already exists
        initialContent = await _pullFromRemoteGit(workplace);
        await jsonFile.writeAsString(initialContent.toJsonString());
        workplace = workplace.copyWith(lastSyncedAt: DateTime.now());
      } catch (e) {
        debugPrint('Remote Git workspace.json not found or empty, creating local initial file: $e');
        initialContent = WorkplaceContent.empty(workplace);
        await jsonFile.writeAsString(initialContent.toJsonString());
        // Try initial push to remote repo
        try {
          await _pushToRemoteGit(workplace, initialContent.toJsonString(), message: 'Initial commit from PostPilot');
          workplace = workplace.copyWith(lastSyncedAt: DateTime.now());
        } catch (pushErr) {
          debugPrint('Initial push notice: $pushErr');
        }
      }
    } else {
      // Local folder only
      if (!jsonFile.existsSync()) {
        initialContent = WorkplaceContent.empty(workplace);
        await jsonFile.writeAsString(initialContent.toJsonString());
      }
    }

    // 3. Register workplace and make it active
    final updated = [...workplaces, workplace];
    await _saveRegistry(updated, activeId: workplace.id);
    return workplace;
  }

  @override
  Future<void> updateWorkplace(WorkplaceEntity workplace) async {
    final workplaces = await getWorkplaces();
    final updated = workplaces.map((w) => w.id == workplace.id ? workplace.copyWith(updatedAt: DateTime.now()) : w).toList();
    await _saveRegistry(updated);
  }

  @override
  Future<void> deleteWorkplace(String id) async {
    final workplaces = await getWorkplaces();
    final filtered = workplaces.where((w) => w.id != id).toList();
    final activeId = await _readActiveId();
    final newActive = activeId == id ? (filtered.isNotEmpty ? filtered.first.id : null) : activeId;
    await _saveRegistry(filtered, activeId: newActive);
  }

  @override
  Future<WorkplaceContent> loadWorkplaceContent(WorkplaceEntity workplace) async {
    final file = File(p.join(workplace.folderPath, _workplaceFileName));
    if (!file.existsSync()) {
      final initial = WorkplaceContent.empty(workplace);
      await file.writeAsString(initial.toJsonString());
      return initial;
    }
    final contentStr = await file.readAsString();
    return WorkplaceContent.fromJsonString(contentStr, fallbackWorkplace: workplace);
  }

  @override
  Future<void> saveWorkplaceContent(WorkplaceEntity workplace, WorkplaceContent content) async {
    final dir = Directory(workplace.folderPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(p.join(workplace.folderPath, _workplaceFileName));
    final jsonStr = content.toJsonString();
    await file.writeAsString(jsonStr);

    // If git connected, auto-sync or notify
    await updateWorkplace(workplace.copyWith(updatedAt: DateTime.now()));
  }

  @override
  Future<void> syncWithGit(WorkplaceEntity workplace, {String? commitMessage}) async {
    if (!workplace.isGitConnected || workplace.gitToken == null) {
      throw Exception('This workplace is not connected to a Git repository or has no token.');
    }
    final content = await loadWorkplaceContent(workplace);
    final jsonStr = content.toJsonString();
    await _pushToRemoteGit(workplace, jsonStr, message: commitMessage ?? 'Update workplace data from PostPilot');
    await updateWorkplace(workplace.copyWith(lastSyncedAt: DateTime.now()));
  }

  @override
  Future<WorkplaceContent> pullFromGit(WorkplaceEntity workplace) async {
    if (!workplace.isGitConnected || workplace.gitToken == null) {
      throw Exception('This workplace is not connected to a Git repository or has no token.');
    }
    final content = await _pullFromRemoteGit(workplace);
    final file = File(p.join(workplace.folderPath, _workplaceFileName));
    await file.writeAsString(content.toJsonString());
    await updateWorkplace(workplace.copyWith(lastSyncedAt: DateTime.now()));
    return content;
  }

  // --- GitHub REST API Git Operations with Tokens (classic) ---

  ({String owner, String repo}) _parseRepo(String url) {
    var cleaned = url.trim().replaceFirst(RegExp(r'\.git$'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^https?://github\.com/'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^git@github\.com:'), '');
    final parts = cleaned.split('/');
    if (parts.length >= 2) {
      return (owner: parts[0], repo: parts[1]);
    }
    throw Exception('Invalid GitHub repository format. Expected "owner/repo" or "https://github.com/owner/repo"');
  }

  Future<WorkplaceContent> _pullFromRemoteGit(WorkplaceEntity workplace) async {
    final repoInfo = _parseRepo(workplace.gitRepoUrl!);
    final branch = workplace.gitBranch;
    final token = workplace.gitToken!;
    final path = 'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}/contents/$_workplaceFileName?ref=$branch';

    try {
      final res = await _dio.get(
        path,
        options: Options(
          headers: {
            'Authorization': 'token $token',
            'Accept': 'application/vnd.github.v3+json',
          },
        ),
      );

      if (res.statusCode == 200 && res.data is Map) {
        final encoding = res.data['encoding'] as String?;
        final contentRaw = res.data['content'] as String;
        String jsonStr;
        if (encoding == 'base64') {
          jsonStr = utf8.decode(base64Decode(contentRaw.replaceAll(RegExp(r'\s'), '')));
        } else {
          jsonStr = contentRaw;
        }
        return WorkplaceContent.fromJsonString(jsonStr, fallbackWorkplace: workplace);
      }
      throw Exception('Unexpected response format from GitHub');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw Exception(
          'No remote "$_workplaceFileName" found on branch "$branch" in repository "${repoInfo.owner}/${repoInfo.repo}". Sync (push) first to create it.',
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
    final branchUrl = 'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}/branches/$branch';
    final authHeader = {
      'Authorization': 'token $token',
      'Accept': 'application/vnd.github.v3+json',
    };

    try {
      final res = await _dio.get(branchUrl, options: Options(headers: authHeader));
      if (res.statusCode == 200) {
        return; // Target branch already exists
      }
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        throw _formatGitDioError(e, repoInfo: repoInfo, branch: branch, operation: 'verifying branch');
      }
    }

    // Branch 404 Not Found: auto-create it from repository's default branch
    try {
      // 1. Get default branch name
      final repoRes = await _dio.get(
        'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}',
        options: Options(headers: authHeader),
      );
      final defaultBranch = (repoRes.data is Map ? repoRes.data['default_branch'] : null) as String? ?? 'main';

      // 2. Get latest commit SHA on default branch
      final refRes = await _dio.get(
        'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}/git/ref/heads/$defaultBranch',
        options: Options(headers: authHeader),
      );
      final defaultSha = (refRes.data is Map && refRes.data['object'] is Map)
          ? refRes.data['object']['sha'] as String?
          : null;

      if (defaultSha != null) {
        // 3. Create the new branch reference
        await _dio.post(
          'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}/git/refs',
          data: {
            'ref': 'refs/heads/$branch',
            'sha': defaultSha,
          },
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

    // 1. Ensure remote branch exists (auto-create from default branch if needed)
    await _ensureBranchExists(repoInfo: repoInfo, branch: branch, token: token);

    final url = 'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}/contents/$_workplaceFileName';

    // 2. Get current SHA if file already exists on this branch
    String? currentSha;
    try {
      final getRes = await _dio.get(
        '$url?ref=$branch',
        options: Options(
          headers: {
            'Authorization': 'token $token',
            'Accept': 'application/vnd.github.v3+json',
          },
        ),
      );
      if (getRes.statusCode == 200 && getRes.data is Map) {
        currentSha = getRes.data['sha'] as String?;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        throw _formatGitDioError(e, repoInfo: repoInfo, branch: branch, operation: 'fetching remote file');
      }
    } catch (_) {}

    // 3. Commit & push file
    try {
      final putRes = await _dio.put(
        url,
        data: {
          'message': message,
          'content': base64Encode(utf8.encode(jsonContent)),
          'branch': branch,
          'sha': ?currentSha,
        },
        options: Options(
          headers: {
            'Authorization': 'token $token',
            'Accept': 'application/vnd.github.v3+json',
          },
        ),
      );

      if (putRes.statusCode != 200 && putRes.statusCode != 201) {
        throw Exception('GitHub responded with HTTP ${putRes.statusCode}');
      }
    } on DioException catch (e) {
      // 409 Conflict: SHA mismatch if someone else pushed to remote; retry with updated SHA
      if (e.response?.statusCode == 409) {
        try {
          final retryGet = await _dio.get(
            '$url?ref=$branch',
            options: Options(
              headers: {
                'Authorization': 'token $token',
                'Accept': 'application/vnd.github.v3+json',
              },
            ),
          );
          if (retryGet.statusCode == 200 && retryGet.data is Map) {
            final latestSha = retryGet.data['sha'] as String?;
            if (latestSha != null && latestSha != currentSha) {
              await _dio.put(
                url,
                data: {
                  'message': message,
                  'content': base64Encode(utf8.encode(jsonContent)),
                  'branch': branch,
                  'sha': latestSha,
                },
                options: Options(
                  headers: {
                    'Authorization': 'token $token',
                    'Accept': 'application/vnd.github.v3+json',
                  },
                ),
              );
              return;
            }
          }
        } catch (_) {}
      }
      throw _formatGitDioError(e, repoInfo: repoInfo, branch: branch, operation: 'pushing workplace to Git');
    }
  }

  Exception _formatGitDioError(
    DioException e, {
    required ({String owner, String repo}) repoInfo,
    required String branch,
    required String operation,
  }) {
    final status = e.response?.statusCode;
    final responseMsg = e.response?.data is Map ? e.response?.data['message'] as String? : null;

    if (status == 401) {
      return Exception('GitHub Authentication failed: Personal Access Token (classic) is invalid or expired.');
    }
    if (status == 403) {
      return Exception(
        'GitHub Access Denied: Token lacks permission for repository "${repoInfo.owner}/${repoInfo.repo}". Ensure your token has "repo" scope.',
      );
    }
    if (status == 404) {
      return Exception(
        'GitHub Not Found: Repository "${repoInfo.owner}/${repoInfo.repo}" or branch "$branch" was not found, or token has insufficient permissions.',
      );
    }
    if (status == 409) {
      if (responseMsg != null && (responseMsg.contains('Secret detected') || responseMsg.contains('Repository rule violations'))) {
        return Exception('GitHub Security Block: A secret or token was detected in the payload and blocked by GitHub Push Protection.');
      }
      return Exception('GitHub Conflict: Remote file has changed. Pull changes before pushing.');
    }
    if (status == 422) {
      return Exception('GitHub Validation error: ${responseMsg ?? "Invalid branch or commit state."}');
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return Exception('Network error: Unable to reach GitHub. Please verify your internet connection.');
    }
    return Exception('GitHub error ($status) during $operation: ${responseMsg ?? e.message}');
  }
}
