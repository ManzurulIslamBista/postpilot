import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/git_link.dart';
import '../../domain/entities/git_sync_exceptions.dart';
import '../../domain/entities/git_sync_results.dart';
import '../../domain/repositories/git_link_repository.dart';
import '../../domain/repositories/local_collection_store.dart';
import '../../domain/services/commit_message.dart';
import '../../domain/usecases/git_commit_push_usecase.dart';
import '../../domain/usecases/git_connect_usecase.dart';
import '../../domain/usecases/git_create_branch_usecase.dart';
import '../../domain/usecases/git_history_usecase.dart';
import '../../domain/usecases/git_pull_usecase.dart';
import '../../domain/usecases/git_status_usecase.dart';
import '../../domain/usecases/git_update_link_settings_usecase.dart';
import 'git_operation_view_model.dart';

typedef RequestsReplacedCallback = void Function(List<int> changedRequestIds, List<int> deletedRequestIds);

final class GitSyncViewModel extends GitOperationViewModel {
  final GitLinkRepository _links;
  final UseCase<GitStatus, GitStatusParams> _statusUseCase;
  final UseCase<GitLink, GitConnectParams> _connectUseCase;
  final UseCase<PushResult, GitCommitPushParams> _commitPushUseCase;
  final UseCase<PullResult, GitPullParams> _pullUseCase;
  final UseCase<ApplyOutcome, int> _discardUseCase;
  final UseCase<List<GitCommitInfo>, GitHistoryParams> _historyUseCase;
  final UseCase<List<String>, int> _listBranchesUseCase;
  final UseCase<GitLink, GitBranchParams> _createBranchUseCase;
  final UseCase<ApplyOutcome, GitBranchParams> _switchBranchUseCase;
  final UseCase<List<GitContributor>, int> _contributorsUseCase;
  final UseCase<GitLink, GitLinkSettingsParams> _updateLinkSettingsUseCase;
  final UseCase<void, int> _disconnectUseCase;

  GitSyncViewModel({
    required super.credentials,
    required super.saveTokenUseCase,
    super.openUri,
    required this._links,
    required this._statusUseCase,
    required this._connectUseCase,
    required this._commitPushUseCase,
    required this._pullUseCase,
    required this._discardUseCase,
    required this._historyUseCase,
    required this._listBranchesUseCase,
    required this._createBranchUseCase,
    required this._switchBranchUseCase,
    required this._contributorsUseCase,
    required this._updateLinkSettingsUseCase,
    required this._disconnectUseCase,
  });

  /// Called after a pull, discard or branch switch rewrote local requests, so open tabs can be closed or reloaded.
  RequestsReplacedCallback? onRequestsReplaced;

  late int _collectionId;
  String _collectionName = '';
  String _defaultCommitMessage = 'Update collection';
  bool _historyLoaded = false;
  bool _branchesLoaded = false;
  bool _contributorsLoaded = false;
  final Map<String, ConflictChoice> _choices = {};
  final Set<String> _loadingLists = {};

  /// The first [load] has established whether the collection is linked.
  bool isLoaded = false;
  GitLink? link;
  GitStatus? status;

  /// Last repository facts the host reported; kept across local-only refreshes, which do not repeat the query.
  GitRepoInfo? repoInfo;
  bool needsPull = false;

  /// The host has answered at least once, so "up to date" is a fact and not just the absence of local changes.
  bool remoteChecked = false;
  List<GitCommitInfo> history = const [];
  List<String> branches = const [];
  List<GitContributor> contributors = const [];
  List<SyncConflict> conflicts = const [];
  String commitMessage = '';
  PushResult? lastPush;

  Map<String, ConflictChoice> get choices => Map.unmodifiable(_choices);
  List<DocChange> get localChanges => status?.localChanges ?? const [];
  bool get hasLocalChanges => localChanges.isNotEmpty;

  /// Unknown access counts as writable so the UI only blocks on a known "no". Without a saved token GitHub answers
  /// anonymously and reports no permissions at all, so its "no" says nothing about the user's rights: unknown too.
  bool get canPush => !hasToken || (repoInfo?.canPush ?? true);

  /// Pushing needs a saved token; [canPush] alone stays true without one, so it has to be asked for separately.
  bool get canCommit => !isBusy && link != null && hasLocalChanges && hasToken && canPush;
  bool get historyLoaded => _historyLoaded;
  bool get branchesLoaded => _branchesLoaded;
  bool get contributorsLoaded => _contributorsLoaded;

  ConflictChoice choiceFor(String uid) => _choices[uid] ?? ConflictChoice.local;

  Future<void> load(int collectionId, {String? collectionName}) async {
    _collectionId = collectionId;
    _collectionName = collectionName?.trim() ?? '';
    _defaultCommitMessage = CommitMessage.fromChanges(_collectionName, const []);
    commitMessage = _defaultCommitMessage;
    await run('Loading…', () async {
      await loadTokenState();
      final existing = await _links.findByCollection(collectionId);
      if (existing == null) {
        link = null;
        isLoaded = true;
        return;
      }
      await _loadStatus();
      isLoaded = true;
      busyLabel = 'Checking GitHub…';
      notifyListeners();
      await _checkRemote();
    });
  }

  Future<bool> refresh({bool checkRemote = false}) =>
      run(checkRemote ? 'Checking GitHub…' : 'Refreshing…', () => _loadStatus(checkRemote: checkRemote));

  Future<bool> connect({
    required String repository,
    String branch = '',
    String basePath = '',
    bool includeSecrets = false,
  }) async {
    final repo = parseRepositoryOrReport(repository);
    if (repo == null) return false;
    return run('Connecting to ${repo.fullName}…', guardsClose: true, () async {
      link = await _connectUseCase(GitConnectParams(
        collectionId: _collectionId,
        repo: repo,
        branch: branch.trim(),
        basePath: _normalizeFolder(basePath),
        includeSecrets: includeSecrets,
      ));
      needsPull = false;
      _forgetLoadedLists();
      await _loadStatus();
      infoMessage = 'Connected to ${repo.fullName}.';
      await _checkRemote();
    });
  }

  Future<bool> commitPush() {
    final typed = commitMessage.trim();
    final message = typed.isEmpty ? _defaultCommitMessage : typed;
    return run('Committing and pushing…', guardsClose: true, () async {
      lastPush = null;
      final pushed = await _commitPushUseCase(GitCommitPushParams(collectionId: _collectionId, message: message));
      lastPush = pushed;
      _markInSync();
      commitMessage = _defaultCommitMessage;
      _historyLoaded = false;
      await _loadStatus();
    });
  }

  Future<bool> pull() => _pull(null, 'Pulling…');

  /// Pulls again with the decisions in [choices] (default: keep mine) for the conflicts of the last pull.
  Future<bool> applyResolutions() =>
      _pull({for (final conflict in conflicts) conflict.uid: choiceFor(conflict.uid)}, 'Applying merge…');

  void setChoice(String uid, ConflictChoice choice) {
    _choices[uid] = choice;
    notifyListeners();
  }

  /// Drops the pending conflicts without touching anything: a pull with conflicts applies nothing.
  void cancelConflicts() {
    if (conflicts.isEmpty && _choices.isEmpty) return;
    _clearConflicts();
    notifyListeners();
  }

  Future<bool> discard() => run('Discarding local changes…', guardsClose: true, () async {
        lastPush = null;
        final outcome = await _discardUseCase(_collectionId);
        await _loadStatus();
        infoMessage = 'Local changes discarded.';
        _replaced(outcome.changedRequestIds, outcome.deletedRequestIds);
      });

  Future<bool> loadHistory() => run('Loading history…', () async {
        history = await _historyUseCase(GitHistoryParams(collectionId: _collectionId));
        _historyLoaded = true;
      }, exclusive: false);

  Future<bool> ensureHistory() => _ensure(_historyLoaded, 'history', loadHistory);

  Future<bool> loadBranches() => run('Loading branches…', () async {
        branches = await _listBranchesUseCase(_collectionId);
        _branchesLoaded = true;
      }, exclusive: false);

  Future<bool> ensureBranches() => _ensure(_branchesLoaded, 'branches', loadBranches);

  Future<bool> createBranch(String name) {
    final branch = name.trim();
    if (branch.isEmpty) {
      reportError('Enter a branch name.');
      return Future.value(false);
    }
    return run('Creating branch $branch…', guardsClose: true, () async {
      link = await _createBranchUseCase(GitBranchParams(collectionId: _collectionId, branch: branch));
      _markInSync();
      _historyLoaded = false;
      if (_branchesLoaded && !branches.contains(branch)) branches = [...branches, branch];
      await _loadStatus();
      infoMessage = 'Created branch $branch and switched to it. Your local changes stay local.';
    });
  }

  Future<bool> switchBranch(String name) => run('Switching to $name…', guardsClose: true, () async {
        lastPush = null;
        final outcome = await _switchBranchUseCase(GitBranchParams(collectionId: _collectionId, branch: name));
        _markInSync();
        _historyLoaded = false;
        await _loadStatus();
        infoMessage = 'Switched to $name.';
        _replaced(outcome.changedRequestIds, outcome.deletedRequestIds);
      });

  Future<bool> loadContributors() => run('Loading contributors…', () async {
        contributors = await _contributorsUseCase(_collectionId);
        _contributorsLoaded = true;
      }, exclusive: false);

  Future<bool> ensureContributors() => _ensure(_contributorsLoaded, 'contributors', loadContributors);

  Future<bool> setIncludeSecrets(bool value) => run('Updating settings…', guardsClose: true, () async {
        link = await _updateLinkSettingsUseCase(
          GitLinkSettingsParams(collectionId: _collectionId, includeSecrets: value),
        );
        await _loadStatus();
      });

  Future<bool> disconnect() => run('Disconnecting…', guardsClose: true, () async {
        await _disconnectUseCase(_collectionId);
        link = null;
        status = null;
        repoInfo = null;
        needsPull = false;
        remoteChecked = false;
        lastPush = null;
        commitMessage = _defaultCommitMessage;
        _clearConflicts();
        _forgetLoadedLists();
        _branchesLoaded = false;
        branches = const [];
        _contributorsLoaded = false;
        contributors = const [];
        infoMessage = 'Disconnected. The collection stays on this device and the repository is unchanged.';
      });

  @override
  void handleError(Object error, [StackTrace? stackTrace]) {
    if (error is GitNotFastForwardException) needsPull = true;
    super.handleError(error, stackTrace);
  }

  @override
  Future<void> onTokenSaved() async {
    if (link != null) await _checkRemote();
  }

  Future<bool> _pull(ConflictResolutions? resolutions, String label) => run(label, guardsClose: true, () async {
        lastPush = null;
        final result = await _pullUseCase(GitPullParams(collectionId: _collectionId, resolutions: resolutions));
        switch (result) {
          case PullConflicts(conflicts: final found):
            _setConflicts(found);
          case PullUpToDate():
            _clearConflicts();
            _markInSync();
            infoMessage = 'Already up to date.';
            await _loadStatus();
          case PullApplied applied:
            _clearConflicts();
            _markInSync();
            _historyLoaded = false;
            infoMessage = _describePull(applied);
            await _loadStatus();
            _replaced(applied.changedRequestIds, applied.deletedRequestIds);
        }
      });

  /// A tab switch notifies more than once, so a list that is already on its way is not requested again.
  Future<bool> _ensure(bool loaded, String list, Future<bool> Function() load) async {
    if (loaded || !_loadingLists.add(list)) return true;
    try {
      return await load();
    } finally {
      _loadingLists.remove(list);
    }
  }

  Future<void> _loadStatus({bool checkRemote = false}) async {
    final result = await _statusUseCase(GitStatusParams(collectionId: _collectionId, checkRemote: checkRemote));
    status = result;
    link = result.link;
    _followChangesInMessage();
    repoInfo = result.repoInfo ?? repoInfo;
    final behind = result.behind;
    if (behind != null) {
      needsPull = behind;
      remoteChecked = true;
    }
  }

  /// The default commit message says what changed ("Change 1 request in Users API", the first names under it), so
  /// the Git history reads well without the person typing anything. A message they have edited is left alone.
  void _followChangesInMessage() {
    final previous = _defaultCommitMessage;
    _defaultCommitMessage = CommitMessage.fromChanges(_collectionName, localChanges);
    if (commitMessage == previous) commitMessage = _defaultCommitMessage;
  }

  /// The remote query needs the network; when it fails the local status already on screen stays valid.
  Future<void> _checkRemote() async {
    try {
      await _loadStatus(checkRemote: true);
    } catch (error, stackTrace) {
      handleError(error, stackTrace);
    }
  }

  void _setConflicts(List<SyncConflict> found) {
    conflicts = found;
    _choices
      ..clear()
      ..addEntries(found.map((conflict) => MapEntry(conflict.uid, ConflictChoice.local)));
  }

  void _clearConflicts() {
    conflicts = const [];
    _choices.clear();
  }

  void _markInSync() {
    needsPull = false;
    remoteChecked = true;
  }

  void _forgetLoadedLists() {
    history = const [];
    _historyLoaded = false;
  }

  void _replaced(List<int> changedRequestIds, List<int> deletedRequestIds) =>
      onRequestsReplaced?.call(changedRequestIds, deletedRequestIds);

  static String _normalizeFolder(String input) =>
      input.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');

  static String _describePull(PullApplied applied) {
    final parts = [
      if (applied.added > 0) '${applied.added} added',
      if (applied.updated > 0) '${applied.updated} updated',
      if (applied.deleted > 0) '${applied.deleted} deleted',
    ];
    return parts.isEmpty ? 'Pulled the latest changes.' : 'Pulled from GitHub: ${parts.join(', ')}.';
  }
}
