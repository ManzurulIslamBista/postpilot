import 'dart:io';
import 'package:path/path.dart' as p;
import '../domain/services/github_workflow_builder.dart';
import 'ci_workflow_writer.dart';

CiWorkflowWriter createCiWorkflowWriter() => const IoCiWorkflowWriter();

/// Reads and writes real folders with `dart:io`.
final class IoCiWorkflowWriter implements CiWorkflowWriter {
  const IoCiWorkflowWriter();

  @override
  bool get canWrite => true;

  @override
  Future<String?> findRepositoryRoot(String folderPath) async {
    try {
      var dir = Directory(p.normalize(p.absolute(folderPath)));
      // `.git` is a folder in a clone and a file in a worktree or a submodule.
      for (var depth = 0; depth < 64; depth++) {
        final marker = p.join(dir.path, '.git');
        if (await Directory(marker).exists() || await File(marker).exists()) return dir.path;
        final parent = dir.parent;
        if (parent.path == dir.path) return null;
        dir = parent;
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  @override
  String workspacePathIn(String repositoryRoot, String workspaceFolder) {
    final file = p.join(p.normalize(p.absolute(workspaceFolder)), 'workspace.json');
    return p.split(p.relative(file, from: repositoryRoot)).join('/');
  }

  @override
  Future<bool> workspaceFileExists(String workspaceFolder) => File(p.join(workspaceFolder, 'workspace.json')).exists();

  @override
  Future<WorkflowSaveResult> save(String repositoryRoot, String yaml, {bool overwrite = false}) async {
    final file = File(p.join(repositoryRoot, '.github', 'workflows', 'postpilot.yml'));
    const shown = GithubWorkflowBuilder.path;
    try {
      var replaced = false;
      if (await file.exists()) {
        final existing = await file.readAsString();
        if (_unix(existing) == _unix(yaml)) return WorkflowUnchanged(shown);
        if (!overwrite) return WorkflowNeedsConfirmation(shown);
        replaced = true;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(yaml, flush: true);
      return WorkflowSaved(shown, replaced: replaced);
    } on FileSystemException catch (e) {
      return WorkflowSaveFailed('Could not write $shown in ${p.basename(repositoryRoot)}: ${e.message}${e.path == null ? '' : ' (${e.path})'}. Check the folder is writable.');
    }
  }

  static String _unix(String text) => text.replaceAll('\r\n', '\n');
}
