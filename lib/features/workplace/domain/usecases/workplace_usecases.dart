import '../entities/workplace_content.dart';
import '../entities/workplace_entity.dart';
import '../repositories/workplace_repository.dart';

final class GetWorkplacesUseCase {
  final WorkplaceRepository _repository;
  const GetWorkplacesUseCase(this._repository);

  Future<List<WorkplaceEntity>> call() => _repository.getWorkplaces();
  Future<WorkplaceEntity?> getActive() => _repository.getActiveWorkplace();
}

final class CreateWorkplaceUseCase {
  final WorkplaceRepository _repository;
  const CreateWorkplaceUseCase(this._repository);

  Future<WorkplaceEntity> call({
    required String name,
    required String folderPath,
    String? gitRepoUrl,
    String? gitBranch,
    String? gitToken,
  }) =>
      _repository.createWorkplace(
        name: name,
        folderPath: folderPath,
        gitRepoUrl: gitRepoUrl,
        gitBranch: gitBranch,
        gitToken: gitToken,
      );
}

final class SwitchWorkplaceUseCase {
  final WorkplaceRepository _repository;
  const SwitchWorkplaceUseCase(this._repository);

  Future<WorkplaceContent> call(WorkplaceEntity workplace) async {
    await _repository.setActiveWorkplace(workplace.id);
    return _repository.loadWorkplaceContent(workplace);
  }
}

final class SaveWorkplaceContentUseCase {
  final WorkplaceRepository _repository;
  const SaveWorkplaceContentUseCase(this._repository);

  Future<void> call(WorkplaceEntity workplace, WorkplaceContent content) =>
      _repository.saveWorkplaceContent(workplace, content);
}

final class SyncWorkplaceUseCase {
  final WorkplaceRepository _repository;
  const SyncWorkplaceUseCase(this._repository);

  Future<void> push(WorkplaceEntity workplace, {String? message}) =>
      _repository.syncWithGit(workplace, commitMessage: message);

  Future<WorkplaceContent> pull(WorkplaceEntity workplace) =>
      _repository.pullFromGit(workplace);
}
