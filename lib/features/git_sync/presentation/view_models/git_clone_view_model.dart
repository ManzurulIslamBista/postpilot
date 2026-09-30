import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/git_link.dart';
import '../../domain/usecases/git_clone_usecase.dart';
import '../../domain/usecases/git_discover_usecase.dart';
import 'git_operation_view_model.dart';

final class GitCloneViewModel extends GitOperationViewModel {
  final UseCase<List<DiscoveredCollection>, GitDiscoverParams> _discoverUseCase;
  final UseCase<GitLink, GitCloneParams> _cloneUseCase;

  GitCloneViewModel({
    required super.credentials,
    required super.saveTokenUseCase,
    super.openUri,
    required this._discoverUseCase,
    required this._cloneUseCase,
  });

  List<DiscoveredCollection> found = const [];
  DiscoveredCollection? selected;

  /// A search finished, so an empty [found] means "nothing there" rather than "not searched yet".
  bool hasSearched = false;

  RepoRef? _repo;
  String _branch = GitOperationViewModel.defaultBranch;

  bool get canClone => !isBusy && selected != null;

  Future<void> load() async {
    await loadTokenState();
    notifyListeners();
  }

  Future<bool> discover({required String repository, String branch = GitOperationViewModel.defaultBranch}) async {
    final repo = parseRepositoryOrReport(repository);
    if (repo == null) return false;
    final branchName = branch.trim().isEmpty ? GitOperationViewModel.defaultBranch : branch.trim();
    return run('Searching ${repo.fullName}…', () async {
      _forgetSearch();
      final results = await _discoverUseCase(GitDiscoverParams(repo: repo, branch: branchName));
      _repo = repo;
      _branch = branchName;
      found = results;
      selected = results.length == 1 ? results.first : null;
      hasSearched = true;
    });
  }

  void select(DiscoveredCollection collection) {
    selected = collection;
    notifyListeners();
  }

  /// The typed repository or branch no longer matches the results shown, so they are dropped.
  void resetSearch() {
    if (!hasSearched && found.isEmpty && selected == null) return;
    _forgetSearch();
    notifyListeners();
  }

  /// The id of the new local collection, or null when nothing was chosen or cloning failed.
  Future<int?> clone() async {
    final repo = _repo;
    final chosen = selected;
    if (repo == null || chosen == null) return null;
    int? collectionId;
    await run('Cloning ${chosen.name}…', () async {
      final link = await _cloneUseCase(GitCloneParams(repo: repo, branch: _branch, basePath: chosen.basePath));
      collectionId = link.collectionId;
    });
    return collectionId;
  }

  void _forgetSearch() {
    found = const [];
    selected = null;
    hasSearched = false;
    _repo = null;
  }
}
