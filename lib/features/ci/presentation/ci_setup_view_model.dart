import 'package:flutter/foundation.dart';
import '../../collections/domain/repositories/collection_repository.dart';
import '../../environments/domain/entities/environment_entity.dart';
import '../../environments/domain/repositories/environment_repository.dart';
import '../../environments/domain/repositories/global_variable_repository.dart';
import '../../safety/domain/services/production_detector.dart';
import '../data/ci_workflow_writer.dart';
import '../domain/entities/ci_options.dart';
import '../domain/services/ci_options_validator.dart';
import '../domain/services/ci_secret_mapper.dart';
import '../domain/services/github_workflow_builder.dart';
import '../domain/services/other_ci_builders.dart';

/// Which kind of file the dialog shows.
enum CiTarget {
  github('GitHub Actions', '.github/workflows/postpilot.yml'),
  gitlab('GitLab CI', '.gitlab-ci.yml'),
  shell('Shell script', 'postpilot-ci.sh');

  final String label;
  final String fileName;
  const CiTarget(this.label, this.fileName);
}

/// The open workplace, as far as the CI setup needs to know it.
final class CiProject {
  /// The workplace folder on disk; null when there is none (a browser keeps workplaces in its storage).
  final String? folderPath;
  final String name;
  const CiProject({this.folderPath, this.name = ''});
}

/// The secret variables of an environment, for the choice of environment.
final class CiEnvironment {
  final String name;
  final List<String> secretVariables;
  const CiEnvironment(this.name, this.secretVariables);
}

/// State of the "Set up CI" dialog: the choices, the three generated files and saving the GitHub one into the
/// repository of the workplace. The files are rebuilt from [options] whenever a choice changes, never edited.
final class CiSetupViewModel with ChangeNotifier {
  final EnvironmentRepository _environments;
  final GlobalVariableRepository _globals;
  final CollectionRepository _collections;
  final CiWorkflowWriter _writer;
  final CiProject project;
  final List<String> _productionWords;
  bool _disposed = false;

  CiSetupViewModel({
    required this._environments,
    required this._globals,
    required this._collections,
    required this._writer,
    required this.project,
    this._productionWords = const [],
  });

  bool isLoading = true;
  List<CiEnvironment> environments = const [];
  List<String> collectionNames = const [];
  List<String> _globalSecrets = const [];

  /// The folder that holds `.git`, when the workplace is inside a repository.
  String? repositoryRoot;
  bool workspaceFileFound = false;

  CiOptions options = const CiOptions();
  CiTarget target = CiTarget.github;
  bool isSaving = false;

  /// What the last save said, and whether it is good news.
  String? saveMessage;
  bool saveFailed = false;

  /// A secret variable that cannot become an environment variable, with why (see `CiSecretMapper`).
  List<String> skippedSecrets = const [];

  /// Whether this platform can write into a repository folder; a browser cannot, and offers a download instead.
  bool get canWriteFiles => _writer.canWrite;

  bool get canSaveToRepository => _writer.canWrite && repositoryRoot != null && !isSaving && problems.isEmpty;

  /// Why the file cannot be saved to the repository, for the footer; null when it can.
  String? get saveBlocker {
    if (!_writer.canWrite) {
      return 'A browser cannot write files: copy or download the YAML and put it in .github/workflows/postpilot.yml of your repository.';
    }
    if (project.folderPath == null) return 'This workplace has no folder on disk: copy the YAML into .github/workflows/postpilot.yml of your repository.';
    if (repositoryRoot == null) {
      return 'The workplace folder is not inside a Git repository: copy the YAML into .github/workflows/postpilot.yml of the repository that holds your workspace.json.';
    }
    return null;
  }

  Map<String, String> get problems => CiOptionsValidator.problems(options);

  /// The generated text of [target]; null while a choice has a problem.
  String? get text {
    if (problems.isNotEmpty) return null;
    return switch (target) {
      CiTarget.github => GithubWorkflowBuilder.build(options),
      CiTarget.gitlab => GitlabCiBuilder.build(options),
      CiTarget.shell => ShellScriptBuilder.build(options),
    };
  }

  /// Whether the environment chosen looks like production (so the lock matters).
  bool get environmentLooksProduction {
    final name = options.environment;
    return name != null && ProductionDetector.isProduction(name, extraWords: _productionWords);
  }

  Future<void> load({String? collectionName, String? preferredEnvironment}) async {
    final all = await _environments.watchAll().first;
    final built = <CiEnvironment>[];
    for (final e in all) {
      built.add(CiEnvironment(e.name, await _secretNamesOf(e)));
    }
    final globals = await _globals.watchAll().first;
    final collections = await _collections.watchCollections().first;
    if (_disposed) return;
    environments = built;
    _globalSecrets = [for (final g in globals) if (g.isSecret && g.enabled) g.key];
    collectionNames = [for (final c in collections) c.name];
    final active = preferredEnvironment ?? all.where((e) => e.isActive).firstOrNull?.name ?? all.firstOrNull?.name;
    final folder = project.folderPath;
    String? root;
    var path = options.workspacePath;
    if (folder != null) {
      root = await _writer.findRepositoryRoot(folder);
      workspaceFileFound = await _writer.workspaceFileExists(folder);
      if (root != null) path = _writer.workspacePathIn(root, folder);
    }
    if (_disposed) return;
    repositoryRoot = root;
    options = options.copyWith(
      environment: active,
      collection: collectionName != null && collectionNames.contains(collectionName) ? collectionName : null,
      workspacePath: path,
    );
    _refreshSecrets();
    isLoading = false;
    notifyListeners();
  }

  Future<List<String>> _secretNamesOf(EnvironmentEntity environment) async {
    final variables = await _environments.watchVariables(environment.id).first;
    return [for (final v in variables) if (v.isSecret && v.enabled) v.key];
  }

  /// The secrets to give the job: the secret variables of the chosen environment, and the secret globals, which every
  /// environment can see.
  void _refreshSecrets() {
    final env = environments.where((e) => e.name == options.environment).firstOrNull;
    final mapping = CiSecretMapper.map([...?env?.secretVariables, ..._globalSecrets]);
    skippedSecrets = mapping.skipped;
    options = options.copyWith(secrets: mapping.secrets);
  }

  void _change(CiOptions Function(CiOptions) edit, {bool secrets = false}) {
    options = edit(options);
    if (secrets) _refreshSecrets();
    saveMessage = null;
    notifyListeners();
  }

  void setTarget(CiTarget value) {
    target = value;
    notifyListeners();
  }

  void setEnvironment(String? name) => _change((o) => o.copyWith(environment: name), secrets: true);
  void setCollection(String? name) => _change((o) => o.copyWith(collection: name));
  void setWorkspacePath(String value) => _change((o) => o.copyWith(workspacePath: value));
  void setSchedule(CiSchedulePreset value) => _change((o) => o.copyWith(schedule: value));
  void setCustomCron(String value) => _change((o) => o.copyWith(customCron: value));
  void setFailOnSkip(bool value) => _change((o) => o.copyWith(failOnSkip: value));
  void setAllowProduction(bool value) => _change((o) => o.copyWith(allowProduction: value));
  void setBail(bool value) => _change((o) => o.copyWith(bail: value));
  void setPostpilotRef(String value) => _change((o) => o.copyWith(postpilotRef: value));
  void setOpenIssue(bool value) => _change((o) => o.copyWith(openIssueOnFailure: value));

  /// Writes the GitHub workflow into the repository. [overwrite] replaces a different file that is already there; the
  /// dialog asks first, which is why the first call never does. Returns what happened so the dialog can ask.
  Future<WorkflowSaveResult> saveToRepository({bool overwrite = false}) async {
    final root = repositoryRoot;
    if (root == null || problems.isNotEmpty) {
      return WorkflowSaveFailed(saveBlocker ?? problems.values.first);
    }
    isSaving = true;
    saveMessage = null;
    notifyListeners();
    final result = await _writer.save(root, GithubWorkflowBuilder.build(options), overwrite: overwrite);
    if (_disposed) return result;
    isSaving = false;
    switch (result) {
      case WorkflowSaved(:final path, :final replaced):
        saveFailed = false;
        saveMessage = replaced
            ? 'Replaced $path. Commit and push it, together with your workspace.json, for GitHub to run it.'
            : 'Saved $path. Commit and push it, together with your workspace.json, for GitHub to run it.';
      case WorkflowUnchanged(:final path):
        saveFailed = false;
        saveMessage = '$path already holds exactly this workflow.';
      case WorkflowNeedsConfirmation():
        saveMessage = null;
      case WorkflowSaveFailed(:final message):
        saveFailed = true;
        saveMessage = message;
    }
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
