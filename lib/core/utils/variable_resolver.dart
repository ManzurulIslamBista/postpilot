import '../constants/app_constants.dart';
import 'dynamic_variables.dart';

/// Resolves `{{variableName}}` tokens against layered variable scopes ordered
/// highest-precedence first (Postman order: active environment > collection >
/// globals) — the first scope holding a key wins. A value may itself hold
/// `{{other}}` tokens, which are resolved in turn; a variable is never
/// expanded inside its own value, so cycles stay as-is. A name no scope holds
/// falls back to a built-in `{{$guid}}`-style [DynamicVariables]; anything
/// still unresolved is left as-is so the user can see what's missing.
final class VariableResolver {
  /// Longest chain of variables referencing variables that is expanded.
  static const _maxDepth = 10;

  final List<Map<String, String>> scopes;

  /// Generates the `{{$name}}` values; null means [DynamicVariables.shared].
  final DynamicVariables? dynamicVariables;

  const VariableResolver.layered(this.scopes, [this.dynamicVariables]);

  /// Single flat scope, for callers that already hold one merged map.
  VariableResolver(Map<String, String> variables, [this.dynamicVariables]) : scopes = [variables];

  String? lookup(String key) {
    for (final scope in scopes) {
      final value = scope[key];
      if (value != null) return value;
    }
    return null;
  }

  String resolve(String input) => _resolve(input, const {}, _Budget());

  Map<String, String> resolveMap(Map<String, String> input) =>
      input.map((key, value) => MapEntry(key, resolve(value)));

  String _resolve(String input, Set<String> expanding, _Budget budget) =>
      input.replaceAllMapped(AppConstants.variablePattern, (m) {
        final key = m[1]!;
        final value = lookup(key);
        if (value == null) return (dynamicVariables ?? DynamicVariables.shared).resolve(key) ?? m[0]!;
        if (expanding.contains(key) || expanding.length >= _maxDepth || !budget.spend(value.length)) return m[0]!;
        return _resolve(value, {...expanding, key}, budget);
      });

  /// Most variable values expanded, and most characters of them, in one
  /// [resolve] call. The depth limit alone still lets `{{v0}}` .. `{{v9}}`,
  /// each repeating the next thirty times, expand about 30^10 times.
  static const _maxExpansions = 20000;
  static const _maxExpandedChars = 32 * 1024 * 1024;
}

/// What is left of the [VariableResolver] expansion allowance; a token met
/// after it runs out stays unresolved, like one that hit the depth limit.
final class _Budget {
  int _expansions = VariableResolver._maxExpansions;
  int _chars = VariableResolver._maxExpandedChars;

  bool spend(int chars) {
    if (_expansions <= 0 || _chars < chars) return false;
    _expansions--;
    _chars -= chars;
    return true;
  }
}
