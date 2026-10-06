import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../git_sync/domain/services/secret_names.dart';

/// Fills in the `{{variables}}` of a History entry for a file that leaves the
/// app (a HAR export), so its URLs are absolute and readable, without ever
/// writing a secret: a variable that is secret (by its name, or because the user
/// marked it secret) is left as `{{name}}`, and so is a variable whose value
/// refers to one. Built-in `{{$guid}}`-style names are left alone too: they would
/// draw a different value on every export.
final class HistoryTemplateExpander {
  final Map<String, String> _values;

  HistoryTemplateExpander._(this._values);

  /// The values of [resolver] without the secret ones. The first scope that holds a name wins, as in a send.
  factory HistoryTemplateExpander.safe(VariableResolver resolver, {Set<String> secretKeys = const {}}) {
    final values = <String, String>{};
    for (final scope in resolver.scopes) {
      for (final entry in scope.entries) {
        values.putIfAbsent(entry.key, () => entry.value);
      }
    }
    values.removeWhere((key, _) => secretKeys.contains(key) || SecretNames.looksSecretKey(key));
    return HistoryTemplateExpander._(values);
  }

  /// Nothing is filled in.
  static final none = HistoryTemplateExpander._(const {});

  /// A value may refer to another variable; this stops a loop.
  static const _maxDepth = 6;

  String call(String text) => _expand(text, 0);

  String _expand(String text, int depth) => text.replaceAllMapped(AppConstants.variablePattern, (m) {
        final value = _values[m[1]!];
        if (value == null || depth >= _maxDepth) return m[0]!;
        return _expand(value, depth + 1);
      });
}
