import '../entities/workplace_content.dart';
import '../entities/workplace_entity.dart';

abstract interface class WorkplaceRepository {
  /// Returns all registered workplaces.
  Future<List<WorkplaceEntity>> getWorkplaces();

  /// Gets the currently active workplace, or null if none is selected.
  Future<WorkplaceEntity?> getActiveWorkplace();

  /// Sets the active workplace ID.
  Future<void> setActiveWorkplace(String id);

  /// Creates and registers a new workplace, initializing its local folder
  /// and single `workspace.json` file.
  Future<WorkplaceEntity> createWorkplace({
    required String name,
    required String folderPath,
    String? gitRepoUrl,
    String? gitBranch,
    String? gitToken,
  });

  /// Updates workplace metadata (such as git settings or folder).
  Future<void> updateWorkplace(WorkplaceEntity workplace);

  /// Removes a workplace from the registry.
  Future<void> deleteWorkplace(String id);

  /// Loads the entire single JSON file (`workspace.json`) from the workplace folder.
  Future<WorkplaceContent> loadWorkplaceContent(WorkplaceEntity workplace);

  /// Saves the entire content as the single `workspace.json` file inside the workplace folder.
  Future<void> saveWorkplaceContent(WorkplaceEntity workplace, WorkplaceContent content);

  /// Syncs (pushes or commits) the single JSON file to the connected Git repository
  /// using GitHub REST API and Personal Access Token (classic).
  Future<void> syncWithGit(WorkplaceEntity workplace, {String? commitMessage});

  /// Pulls the single JSON file from the connected Git repository and saves it locally.
  Future<WorkplaceContent> pullFromGit(WorkplaceEntity workplace);

  /// Returns the default folder path on this PC for a workplace.
  Future<String> getDefaultWorkplacesDirectory({String? workplaceName});

  /// Opens the native macOS folder selection dialog.
  Future<String?> pickFolder({String? initialPath});
}
