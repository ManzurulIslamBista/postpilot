import 'package:postpilot/features/git_sync/domain/entities/git_link.dart';
import 'package:postpilot/features/git_sync/domain/entities/git_sync_results.dart';
import 'package:postpilot/features/git_sync/domain/repositories/git_host_client.dart';
import 'package:postpilot/features/git_sync/domain/services/git_hash.dart';

final class _Commit {
  final String sha;
  final String? parent;
  final Map<String, String> tree;
  final Set<String> touched;
  final String message;
  final String author;
  final DateTime date;

  _Commit({
    required this.sha,
    required this.parent,
    required this.tree,
    required this.touched,
    required this.message,
    required this.author,
    required this.date,
  });
}

final class _Repo {
  bool isPrivate;
  final branches = <String, String>{};
  final commits = <String, _Commit>{};
  final blobs = <String, String>{};

  _Repo({required this.isPrivate});
}

/// In-memory Git host with real fast-forward semantics: a commit whose parent
/// is not the branch head is rejected, trees are path -> text maps and blob
/// shas are the real Git ones.
class FakeGitHost implements GitHostClient {
  String login;
  bool canPush = true;
  bool tokenValid = true;

  /// Blob downloads so far, and the most that were ever in flight together.
  int blobReads = 0;
  int peakConcurrentBlobReads = 0;

  /// Makes every blob download fail, like a dropped connection.
  bool failBlobReads = false;

  /// Runs at the start of every tree and blob download, that is while a pull or
  /// a branch switch waits on the network, so a test can edit the local
  /// collection at a moment the user could. Not cleared by itself: a hook that
  /// should fire once removes itself.
  void Function()? whileFetching;

  final _repos = <String, _Repo>{};
  var _blobsInFlight = 0;
  var _counter = 0;

  FakeGitHost({this.login = 'alice'});

  /// Creates a repository. With the default README it has a first commit on
  /// [branch]; with empty [files] it stays empty (no commits, no branches).
  RepoRef seedRepo(
    String fullName, {
    Map<String, String> files = const {'README.md': '# Repo\n'},
    String branch = 'main',
    bool isPrivate = true,
  }) {
    final ref = repoRef(fullName);
    final repo = _repos[ref.fullName] = _Repo(isPrivate: isPrivate);
    if (files.isNotEmpty) _append(repo, branch, null, {}, files, 'Initial commit', login);
    return ref;
  }

  RepoRef repoRef(String fullName) => RepoRef.parse(fullName)!;

  String? headOf(RepoRef repo, [String branch = 'main']) => _repo(repo).branches[branch];

  /// Files of the branch head (empty for an unknown branch).
  Map<String, String> filesAt(RepoRef repo, [String branch = 'main']) {
    final r = _repo(repo);
    final head = r.branches[branch];
    return head == null ? {} : Map.of(r.commits[head]!.tree);
  }

  /// A commit made outside PostPilot (another Git client) on top of the head.
  String commitFiles(
    RepoRef repo,
    Map<String, String?> changes, {
    String branch = 'main',
    String message = 'External change',
    String author = 'bob',
  }) {
    final r = _repo(repo);
    return _commitOn(r, branch, r.branches[branch], message, changes, author);
  }

  @override
  Future<String> getAuthenticatedLogin() async {
    if (!tokenValid) throw const GitAuthException('Bad credentials');
    return login;
  }

  @override
  Future<GitRepoInfo> getRepo(RepoRef repo) async {
    final r = _repo(repo);
    return GitRepoInfo(defaultBranch: 'main', canPush: canPush, isPrivate: r.isPrivate, isEmpty: r.branches.isEmpty);
  }

  @override
  Future<RepoRef> createRepo({
    required GitProvider provider,
    required String name,
    required bool private,
    String? description,
  }) async {
    final ref = RepoRef(provider: provider, owner: login, repo: name);
    seedRepo(ref.fullName, isPrivate: private);
    return ref;
  }

  @override
  Future<List<String>> listBranches(RepoRef repo) async => _repo(repo).branches.keys.toList()..sort();

  @override
  Future<String?> getBranchHead(RepoRef repo, String branch) async => _repo(repo).branches[branch];

  @override
  Future<void> createBranch(RepoRef repo, String branch, {required String fromSha}) async {
    final r = _repo(repo);
    if (r.branches.containsKey(branch)) throw GitHostException('Reference already exists: $branch');
    if (!r.commits.containsKey(fromSha)) throw const GitNotFoundException('Commit not found');
    r.branches[branch] = fromSha;
  }

  @override
  Future<RemoteTree> getTree(RepoRef repo, String commitSha, {String pathPrefix = ''}) async {
    whileFetching?.call();
    final commit = _repo(repo).commits[commitSha] ?? (throw const GitNotFoundException('Commit not found'));
    return RemoteTree(
      commitSha: commitSha,
      blobShaByPath: {
        for (final file in commit.tree.entries)
          if (file.key.startsWith(pathPrefix)) file.key: GitHash.blobSha(file.value),
      },
    );
  }

  @override
  Future<String> getBlobText(RepoRef repo, String blobSha) async {
    whileFetching?.call();
    final r = _repo(repo);
    blobReads++;
    _blobsInFlight++;
    if (_blobsInFlight > peakConcurrentBlobReads) peakConcurrentBlobReads = _blobsInFlight;
    await Future<void>.delayed(Duration.zero);
    _blobsInFlight--;
    if (failBlobReads) throw const GitHostException('Connection lost');
    return r.blobs[blobSha] ?? (throw const GitNotFoundException('Blob not found'));
  }

  @override
  Future<String> commit(
    RepoRef repo, {
    required String branch,
    required String parentSha,
    required String message,
    required Map<String, String?> changes,
  }) async {
    final r = _repo(repo);
    if (parentSha.isEmpty) {
      if (r.branches.isNotEmpty) throw const GitNotFastForwardException('The repository already has commits');
      return _commitOn(r, branch, null, message, changes, login);
    }
    if (r.branches[branch] != parentSha) throw const GitNotFastForwardException('Update is not a fast forward');
    return _commitOn(r, branch, parentSha, message, changes, login);
  }

  @override
  Future<List<GitCommitInfo>> listCommits(
    RepoRef repo, {
    required String branch,
    String pathPrefix = '',
    int limit = 30,
  }) async {
    final r = _repo(repo);
    final result = <GitCommitInfo>[];
    for (var sha = r.branches[branch]; sha != null && result.length < limit; sha = r.commits[sha]!.parent) {
      final commit = r.commits[sha]!;
      if (pathPrefix.isNotEmpty && !commit.touched.any((path) => path.startsWith(pathPrefix))) continue;
      result.add(GitCommitInfo(
        sha: commit.sha,
        message: commit.message,
        authorName: commit.author,
        date: commit.date,
      ));
    }
    return result;
  }

  @override
  Future<List<GitContributor>> listContributors(RepoRef repo) async {
    final counts = <String, int>{};
    for (final commit in _repo(repo).commits.values) {
      counts[commit.author] = (counts[commit.author] ?? 0) + 1;
    }
    final logins = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return [for (final name in logins) GitContributor(login: name, contributions: counts[name]!)];
  }

  _Repo _repo(RepoRef repo) => _repos[repo.fullName] ?? (throw GitNotFoundException('Repository not found: ${repo.fullName}'));

  String _commitOn(
    _Repo repo,
    String branch,
    String? parentSha,
    String message,
    Map<String, String?> changes,
    String author,
  ) {
    final tree = parentSha == null ? <String, String>{} : {...repo.commits[parentSha]!.tree};
    final writes = <String, String>{};
    for (final change in changes.entries) {
      final text = change.value;
      if (text == null) {
        if (tree.remove(change.key) == null) throw GitHostException('Cannot delete "${change.key}": no such file.');
      } else {
        writes[change.key] = text;
      }
    }
    return _append(repo, branch, parentSha, tree, writes, message, author, deleted: changes.keys);
  }

  String _append(
    _Repo repo,
    String branch,
    String? parentSha,
    Map<String, String> tree,
    Map<String, String> writes,
    String message,
    String author, {
    Iterable<String> deleted = const [],
  }) {
    final newTree = {...tree, ...writes};
    for (final text in writes.values) {
      repo.blobs[GitHash.blobSha(text)] = text;
    }
    final sha = GitHash.blobSha('commit ${_counter++} ${parentSha ?? ''} $message');
    repo.commits[sha] = _Commit(
      sha: sha,
      parent: parentSha,
      tree: newTree,
      touched: {...writes.keys, ...deleted},
      message: message,
      author: author,
      date: DateTime.utc(2026, 1, 1).add(Duration(minutes: _counter)),
    );
    repo.branches[branch] = sha;
    return sha;
  }
}
