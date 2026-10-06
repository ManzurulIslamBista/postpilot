// Pure Dart interface: the platform writers live in the `_io` and `_stub` files, so this compiles for the web too.
export 'ci_workflow_writer_stub.dart' if (dart.library.io) 'ci_workflow_writer_io.dart' show createCiWorkflowWriter;

/// What saving the workflow file did.
sealed class WorkflowSaveResult {
  const WorkflowSaveResult();
}

/// The file was written ([replaced] when another one was there before, and the person confirmed).
final class WorkflowSaved extends WorkflowSaveResult {
  final String path;
  final bool replaced;
  const WorkflowSaved(this.path, {this.replaced = false});
}

/// The file already holds exactly this text.
final class WorkflowUnchanged extends WorkflowSaveResult {
  final String path;
  const WorkflowUnchanged(this.path);
}

/// A different file is there already; nothing was written. Ask, then save again with `overwrite`.
final class WorkflowNeedsConfirmation extends WorkflowSaveResult {
  final String path;
  const WorkflowNeedsConfirmation(this.path);
}

final class WorkflowSaveFailed extends WorkflowSaveResult {
  final String message;
  const WorkflowSaveFailed(this.message);
}

/// Finds the Git repository of a workplace folder and puts `.github/workflows/postpilot.yml` into it.
abstract interface class CiWorkflowWriter {
  /// Whether this platform can read and write real folders (false in a browser).
  bool get canWrite;

  /// The folder that holds `.git`, looking from [folderPath] upwards; null when [folderPath] is not inside a Git repository.
  Future<String?> findRepositoryRoot(String folderPath);

  /// [workspaceFolder]'s `workspace.json` as a path from [repositoryRoot], with `/` separators.
  String workspacePathIn(String repositoryRoot, String workspaceFolder);

  /// Whether `workspace.json` exists in [workspaceFolder].
  Future<bool> workspaceFileExists(String workspaceFolder);

  /// Writes [yaml] to `<repositoryRoot>/.github/workflows/postpilot.yml`. A different file already there is left
  /// alone and reported as [WorkflowNeedsConfirmation] unless [overwrite]. Line endings do not count as a difference.
  Future<WorkflowSaveResult> save(String repositoryRoot, String yaml, {bool overwrite = false});
}
