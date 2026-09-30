import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/entities/git_link.dart';
import '../../domain/entities/git_sync_results.dart';
import '../../domain/repositories/git_credentials_store.dart';
import '../../domain/repositories/git_host_client.dart';
import 'github_http.dart';

const _pageSize = 100;
const _maxPages = 30;
const _fileMode = '100644';

typedef _TreeEntry = ({String path, String type, String sha});
typedef _TreeListing = ({List<_TreeEntry> entries, bool truncated});

/// [GitHostClient] for github.com, over the REST API only (works on web).
final class GitHubHostClient implements GitHostClient {
  GitHubHostClient(GitCredentialsStore credentials, {Dio? dio}) : _http = GitHubHttp(credentials, dio: dio);

  final GitHubHttp _http;

  @override
  Future<String> getAuthenticatedLogin() async {
    await _http.requireToken();
    final res = (await _http.get('/user')).ensureOk('Your GitHub account');
    return res.read((j) => (j as Map<String, dynamic>)['login'] as String);
  }

  @override
  Future<GitRepoInfo> getRepo(RepoRef repo) async {
    final res = (await _http.get(_repoPath(repo))).ensureOk(_repoLabel(repo));
    final facts = res.read((j) {
      final m = j as Map<String, dynamic>;
      return (
        defaultBranch: m['default_branch'] as String,
        isPrivate: m['private'] as bool,
        canPush: (m['permissions'] as Map<String, dynamic>?)?['push'] == true,
        size: (m['size'] as num?)?.toInt() ?? -1,
      );
    });
    return GitRepoInfo(
      defaultBranch: facts.defaultBranch,
      canPush: facts.canPush,
      isPrivate: facts.isPrivate,
      isEmpty: facts.size == 0 && await _hasNoBranches(repo),
    );
  }

  @override
  Future<RepoRef> createRepo({
    required GitProvider provider,
    required String name,
    required bool private,
    String? description,
  }) async {
    final res = (await _http.post('/user/repos', {
      'name': name,
      'private': private,
      if (description != null && description.isNotEmpty) 'description': description,
      'auto_init': true,
    }))
        .ensureOk('Repository $name');
    return res.read((j) {
      final m = j as Map<String, dynamic>;
      return RepoRef(
        provider: provider,
        owner: (m['owner'] as Map<String, dynamic>)['login'] as String,
        repo: m['name'] as String,
      );
    });
  }

  @override
  Future<List<String>> listBranches(RepoRef repo) async {
    final names = <String>[];
    for (var page = 1; page <= _maxPages; page++) {
      final res = await _http.get('${_repoPath(repo)}/branches', query: {'per_page': _pageSize, 'page': page});
      if (res.isEmptyRepository) break;
      final batch = res
          .ensureOk(_repoLabel(repo))
          .read((j) => [for (final b in j as List) (b as Map<String, dynamic>)['name'] as String]);
      names.addAll(batch);
      if (batch.length < _pageSize) break;
    }
    return names;
  }

  @override
  Future<String?> getBranchHead(RepoRef repo, String branch) async {
    final res = await _http.get('${_repoPath(repo)}/git/ref/heads/${_encodePath(branch)}');
    if (res.status == 404 || res.isEmptyRepository) return null;
    return res.ensureOk(_repoLabel(repo)).read((j) => ((j as Map<String, dynamic>)['object'] as Map<String, dynamic>)['sha'] as String);
  }

  @override
  Future<void> createBranch(RepoRef repo, String branch, {required String fromSha}) async {
    (await _http.post('${_repoPath(repo)}/git/refs', {'ref': 'refs/heads/$branch', 'sha': fromSha})).ensureOk(_repoLabel(repo));
  }

  @override
  Future<RemoteTree> getTree(RepoRef repo, String commitSha, {String pathPrefix = ''}) async {
    final treeSha = await _treeShaOf(repo, commitSha);
    final files = <String, String>{};
    final listing = await _listTree(repo, treeSha, recursive: true);
    if (listing.truncated) {
      await _walk(repo, treeSha, '', pathPrefix, files);
    } else {
      for (final e in listing.entries) {
        if (e.type == 'blob' && e.path.startsWith(pathPrefix)) files[e.path] = e.sha;
      }
    }
    return RemoteTree(commitSha: commitSha, blobShaByPath: files);
  }

  @override
  Future<String> getBlobText(RepoRef repo, String blobSha) async {
    final res = (await _http.get('${_repoPath(repo)}/git/blobs/${Uri.encodeComponent(blobSha)}', cacheBust: false))
        .ensureOk('Blob ${_short(blobSha)} of ${repo.fullName}');
    return res.read((j) {
      final m = j as Map<String, dynamic>;
      final content = m['content'] as String;
      if (m['encoding'] == 'utf-8') return content;
      return utf8.decode(base64Decode(content.replaceAll(RegExp(r'\s'), '')));
    });
  }

  @override
  Future<String> commit(
    RepoRef repo, {
    required String branch,
    required String parentSha,
    required String message,
    required Map<String, String?> changes,
  }) async {
    await _http.requireToken();
    var base = parentSha;
    var pending = changes;
    if (parentSha.isEmpty) {
      final writes = {for (final e in changes.entries) if (e.value != null) e.key: e.value};
      if (writes.isEmpty) {
        throw ArgumentError.value(changes, 'changes', 'an empty repository needs at least one file to write');
      }
      final first = writes.entries.first;
      base = await _createInitialCommit(repo, branch: branch, message: message, path: first.key, text: first.value!);
      pending = {for (final e in writes.entries.skip(1)) e.key: e.value};
      if (pending.isEmpty) return base;
    } else {
      if (changes.isEmpty) throw ArgumentError.value(changes, 'changes', 'nothing to commit');
      final head = await getBranchHead(repo, branch);
      if (head != parentSha) {
        throw GitNotFastForwardException(
          head == null
              ? 'Branch "$branch" no longer exists in ${repo.fullName}. Pull, then push again.'
              : 'Branch "$branch" has new commits in ${repo.fullName}. Pull, then push again.',
        );
      }
    }

    final repoPath = _repoPath(repo);
    final baseTree = await _treeShaOf(repo, base);
    final tree = (await _http.post('$repoPath/git/trees', {
      'base_tree': baseTree,
      'tree': [
        for (final e in pending.entries)
          {'path': e.key, 'mode': _fileMode, 'type': 'blob', if (e.value == null) 'sha': null else 'content': e.value},
      ],
    }))
        .ensureOk(_repoLabel(repo));
    final created = (await _http.post('$repoPath/git/commits', {
      'message': message,
      'tree': tree.read(_shaOf),
      'parents': [base],
    }))
        .ensureOk(_repoLabel(repo));
    final commitSha = created.read(_shaOf);
    final moved = await _http.patch('$repoPath/git/refs/heads/${_encodePath(branch)}', {'sha': commitSha, 'force': false});
    if (moved.status == 422 && _isNotFastForward(moved.message)) {
      throw GitNotFastForwardException('Branch "$branch" moved while pushing. Pull, then push again.');
    }
    moved.ensureOk(_repoLabel(repo));
    return commitSha;
  }

  @override
  Future<List<GitCommitInfo>> listCommits(RepoRef repo, {required String branch, String pathPrefix = '', int limit = 30}) async {
    final folder = pathPrefix.replaceFirst(RegExp(r'/+$'), '');
    final res = await _http.get('${_repoPath(repo)}/commits', query: {
      'sha': branch,
      if (folder.isNotEmpty) 'path': folder,
      'per_page': limit.clamp(1, _pageSize),
    });
    if (res.isEmptyRepository) return const [];
    return res
        .ensureOk('Branch "$branch" of ${repo.fullName}')
        .read((j) => [for (final c in j as List) _commitInfo(c)]);
  }

  @override
  Future<List<GitContributor>> listContributors(RepoRef repo) async {
    final res = await _http.get('${_repoPath(repo)}/contributors', query: {'per_page': 50});
    if (res.isEmptyRepository) return const [];
    final ok = res.ensureOk(_repoLabel(repo));
    if (ok.json == null) return const [];
    return ok.read((j) => [
          for (final c in j as List)
            if (c is Map<String, dynamic> && c['login'] is String)
              GitContributor(
                login: c['login'] as String,
                contributions: (c['contributions'] as num).toInt(),
                avatarUrl: c['avatar_url'] as String?,
                profileUrl: c['html_url'] as String?,
              ),
        ]);
  }

  /// A repository without commits cannot be written through the Git Data API,
  /// but the contents API accepts the first file and creates the branch with it.
  Future<String> _createInitialCommit(
    RepoRef repo, {
    required String branch,
    required String message,
    required String path,
    required String text,
  }) async {
    final res = await _http.put('${_repoPath(repo)}/contents/${_encodePath(path)}', {
      'message': message,
      'content': base64Encode(utf8.encode(text)),
      'branch': branch,
    });
    final alreadyHasCommits = res.status == 409 || (res.status == 422 && (res.message ?? '').contains('sha'));
    if (alreadyHasCommits) {
      throw GitNotFastForwardException('${repo.fullName} already has commits now. Pull, then push again.');
    }
    return res
        .ensureOk(_repoLabel(repo))
        .read((j) => ((j as Map<String, dynamic>)['commit'] as Map<String, dynamic>)['sha'] as String);
  }

  Future<bool> _hasNoBranches(RepoRef repo) async {
    final res = await _http.get('${_repoPath(repo)}/branches', query: {'per_page': 1});
    if (res.status == 404 || res.isEmptyRepository) return true;
    return res.ensureOk(_repoLabel(repo)).read((j) => (j as List).isEmpty);
  }

  Future<String> _treeShaOf(RepoRef repo, String commitSha) async {
    final res = (await _http.get('${_repoPath(repo)}/git/commits/${Uri.encodeComponent(commitSha)}', cacheBust: false))
        .ensureOk('Commit ${_short(commitSha)} of ${repo.fullName}');
    return res.read((j) => ((j as Map<String, dynamic>)['tree'] as Map<String, dynamic>)['sha'] as String);
  }

  Future<_TreeListing> _listTree(RepoRef repo, String treeSha, {required bool recursive}) async {
    final res = (await _http.get(
      '${_repoPath(repo)}/git/trees/${Uri.encodeComponent(treeSha)}',
      query: {if (recursive) 'recursive': 1},
      cacheBust: false,
    ))
        .ensureOk('Tree ${_short(treeSha)} of ${repo.fullName}');
    return res.read((j) {
      final m = j as Map<String, dynamic>;
      return (entries: [for (final t in m['tree'] as List) _treeEntry(t)], truncated: m['truncated'] == true);
    });
  }

  /// Recursive listings cap at 100k entries / 7 MB; past that, list one folder
  /// at a time, descending only where files can match [prefix].
  Future<void> _walk(RepoRef repo, String treeSha, String dir, String prefix, Map<String, String> out) async {
    final listing = await _listTree(repo, treeSha, recursive: false);
    if (listing.truncated) {
      throw GitHostException('The repository folder "${dir.isEmpty ? '/' : dir}" has too many entries for GitHub to list');
    }
    for (final e in listing.entries) {
      final path = dir.isEmpty ? e.path : '$dir/${e.path}';
      if (e.type == 'blob') {
        if (path.startsWith(prefix)) out[path] = e.sha;
      } else if (e.type == 'tree') {
        final folder = '$path/';
        if (folder.startsWith(prefix) || prefix.startsWith(folder)) await _walk(repo, e.sha, path, prefix, out);
      }
    }
  }
}

String _repoPath(RepoRef repo) => '/repos/${Uri.encodeComponent(repo.owner)}/${Uri.encodeComponent(repo.repo)}';

String _repoLabel(RepoRef repo) => 'Repository ${repo.fullName}';

/// Encodes each segment but keeps the slashes: branch and file paths are
/// several URL segments.
String _encodePath(String path) => path.split('/').map(Uri.encodeComponent).join('/');

String _short(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;

String _shaOf(Object? json) => (json as Map<String, dynamic>)['sha'] as String;

bool _isNotFastForward(String? message) {
  final text = (message ?? '').toLowerCase();
  return text.contains('fast forward') || text.contains('fast-forward');
}

_TreeEntry _treeEntry(Object? raw) {
  final m = raw as Map<String, dynamic>;
  return (path: m['path'] as String, type: m['type'] as String, sha: m['sha'] as String);
}

GitCommitInfo _commitInfo(Object? raw) {
  final m = raw as Map<String, dynamic>;
  final commit = m['commit'] as Map<String, dynamic>;
  final author = commit['author'] as Map<String, dynamic>;
  return GitCommitInfo(
    sha: m['sha'] as String,
    message: commit['message'] as String,
    authorName: author['name'] as String,
    date: DateTime.parse(author['date'] as String),
    url: m['html_url'] as String?,
  );
}
