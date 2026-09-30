abstract final class AppConstants {
  static const appName = 'PostPilot';
  static const requestTimeout = Duration(seconds: 30);
  static const rootFolderId = 0;

  /// Matches `{{variableName}}` tokens inside URLs, headers and bodies. Names
  /// may hold letters, digits, `_`, `-`, `.` and `$` (e.g. `base-url`, `user.id`).
  static final variablePattern = RegExp(r'\{\{([\w.$-]+)\}\}');
}
