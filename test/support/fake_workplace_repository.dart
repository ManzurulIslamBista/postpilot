import 'package:postpilot/features/workplace/domain/entities/workplace_content.dart';
import 'package:postpilot/features/workplace/domain/entities/workplace_entity.dart';
import 'package:postpilot/features/workplace/domain/repositories/workplace_repository.dart';

/// A [WorkplaceRepository] that lives in memory, for widget tests that mount
/// the whole app (which now reads a `WorkplaceViewModel`) but are not about
/// workplaces: no files, no network, no platform channels.
final class FakeWorkplaceRepository implements WorkplaceRepository {
  final List<WorkplaceEntity> _workplaces = [];
  final Map<String, WorkplaceContent> _contents = {};
  String? _activeId;

  /// What the "platform" can do: desktop-like by default, the web when `usesRealFolders` is false.
  final bool _usesRealFolders;
  final bool _canPickFolder;

  /// Thrown by the next [createWorkplace], to see how the UI reports a failure.
  Object? createError;

  /// How many times the open workplace was pushed to / pulled from Git.
  int syncCalls = 0;
  int pullCalls = 0;

  /// When set, the workplace the repository starts with is connected to this repository.
  final String? _initialGitRepoUrl;

  FakeWorkplaceRepository({this._usesRealFolders = true, this._canPickFolder = false, String? gitRepoUrl}) : _initialGitRepoUrl = gitRepoUrl;

  @override
  bool get usesRealFolders => _usesRealFolders;

  @override
  bool get canPickFolder => _canPickFolder;

  @override
  bool get canRevealFolder => false;

  @override
  String get fileManagerName => 'file manager';

  @override
  Future<List<WorkplaceEntity>> getWorkplaces() async {
    if (_workplaces.isEmpty) {
      final first = _entity('My Workplace', '/fake/My_Workplace').copyWith(gitRepoUrl: _initialGitRepoUrl, gitToken: _initialGitRepoUrl == null ? null : 'token');
      _workplaces.add(first);
      _activeId = first.id;
    }
    return List.of(_workplaces);
  }

  @override
  Future<WorkplaceEntity?> getActiveWorkplace() async {
    final all = await getWorkplaces();
    return all.firstWhere((w) => w.id == _activeId, orElse: () => all.first);
  }

  @override
  Future<void> setActiveWorkplace(String id) async => _activeId = id;

  @override
  Future<WorkplaceEntity> createWorkplace({
    required String name,
    required String folderPath,
    String? gitRepoUrl,
    String? gitBranch,
    String? gitToken,
  }) async {
    await getWorkplaces();
    final error = createError;
    if (error != null) throw error;
    final workplace = _entity(
      name,
      folderPath,
    ).copyWith(gitRepoUrl: gitRepoUrl, gitBranch: gitBranch ?? 'main', gitToken: gitToken);
    _workplaces.add(workplace);
    _activeId = workplace.id;
    return workplace;
  }

  @override
  Future<void> updateWorkplace(WorkplaceEntity workplace) async {
    final index = _workplaces.indexWhere((w) => w.id == workplace.id);
    if (index != -1) _workplaces[index] = workplace;
  }

  @override
  Future<void> deleteWorkplace(String id) async {
    _workplaces.removeWhere((w) => w.id == id);
    if (_activeId == id) _activeId = _workplaces.isEmpty ? null : _workplaces.first.id;
  }

  @override
  Future<WorkplaceContent> loadWorkplaceContent(WorkplaceEntity workplace) async =>
      _contents[workplace.id] ?? WorkplaceContent.empty(workplace);

  @override
  Future<void> saveWorkplaceContent(WorkplaceEntity workplace, WorkplaceContent content) async =>
      _contents[workplace.id] = content;

  @override
  Future<void> syncWithGit(WorkplaceEntity workplace, {String? commitMessage}) async => syncCalls++;

  @override
  Future<WorkplaceContent> pullFromGit(WorkplaceEntity workplace) async {
    pullCalls++;
    return loadWorkplaceContent(workplace);
  }

  @override
  Future<String> getDefaultWorkplacesDirectory({String? workplaceName}) async =>
      '/fake/${workplaceName ?? 'Workplaces'}';

  @override
  Future<String?> pickFolder({String? initialPath}) async => _canPickFolder ? '/picked/folder' : null;

  @override
  Future<void> revealFolder(String folderPath) async {}

  int _sequence = 0;

  WorkplaceEntity _entity(String name, String folder) => WorkplaceEntity(
    id: 'fake-${_sequence++}',
    name: name,
    folderPath: folder,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}
