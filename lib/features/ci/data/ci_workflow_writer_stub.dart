import 'ci_workflow_writer.dart';

/// A browser has no folders to look in or to write to: the YAML is shown to be copied.
CiWorkflowWriter createCiWorkflowWriter() => const _UnsupportedWriter();

final class _UnsupportedWriter implements CiWorkflowWriter {
  const _UnsupportedWriter();

  @override
  bool get canWrite => false;

  @override
  Future<String?> findRepositoryRoot(String folderPath) async => null;

  @override
  String workspacePathIn(String repositoryRoot, String workspaceFolder) => 'workspace.json';

  @override
  Future<bool> workspaceFileExists(String workspaceFolder) async => false;

  @override
  Future<WorkflowSaveResult> save(String repositoryRoot, String yaml, {bool overwrite = false}) async =>
      const WorkflowSaveFailed('A browser cannot write files. Copy the YAML into .github/workflows/postpilot.yml of your repository.');
}
