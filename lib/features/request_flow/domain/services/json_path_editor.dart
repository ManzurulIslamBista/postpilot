import '../../../scripting/domain/evaluator/json_path_resolver.dart';

/// Writes a value at a JSON path (`data.items`, `params.args[6].offset`, `$` for the whole document), the way
/// [JsonPathResolver] reads one. Works on decoded JSON and changes it in place.
abstract final class JsonPathEditor {
  /// [root] with [value] at [path], which is [root] itself when [path] names the whole document. A missing key on
  /// the way is created as an object; an index past the end of a list, or a step into a scalar, throws a
  /// [FormatException] saying which.
  static Object? set(Object? root, String path, Object? value) {
    final steps = JsonPathResolver.segmentsOf(path);
    if (steps.isEmpty) return value;
    Object? current = root;
    for (var i = 0; i < steps.length; i++) {
      final last = i == steps.length - 1;
      final step = steps[i];
      if (current is Map) {
        final key = step.toString();
        if (last) {
          current[key] = value;
        } else {
          current = current[key] ??= <String, Object?>{};
        }
      } else if (current is List) {
        final index = step is int ? step : int.tryParse(step as String);
        if (index == null || index < 0 || index > current.length || (index == current.length && !last)) {
          throw FormatException('There is no item $step to write to in "$path".');
        }
        if (last) {
          index == current.length ? current.add(value) : current[index] = value;
        } else {
          current = current[index];
        }
      } else {
        throw FormatException('"$path" goes through a value that is not an object or a list.');
      }
    }
    return root;
  }

  /// The value at [path], `null` when there is none (a JSON `null` too, as everywhere in the assertions).
  static Object? read(Object? root, String path) => JsonPathResolver.resolve(root, path);
}
