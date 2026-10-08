// Pure Dart (no Flutter).
import '../../../../core/constants/app_constants.dart';
import '../../../scripting/domain/evaluator/response_reader.dart';
import 'created_id_detector.dart';

/// The variables an undo request is sent with, so `{{created.id}}` works in its URL, headers and body.
///
/// `created.id` is the first id, `created.ids` all of them joined by commas (it fits an Odoo `"ids": [{{created.ids}}]`),
/// `created.count` how many. When the create answered with an object, every field of it follows as `created.<field>`
/// (`created.name`, `created.data.code`), nested objects flattened with dots and lists by position (`created.items.0`).
abstract final class CreatedVariables {
  static const prefix = 'created';

  /// Fields kept from one response, and how deep and how long: an undo needs a handful of values, not a whole page.
  static const maxFields = 200;
  static const maxDepth = 4;
  static const maxListItems = 25;
  static const maxValueLength = 2048;

  static Map<String, String> build(CreatedIds ids, Object? responseJson) {
    final fields = <String, String>{};
    if (responseJson is Map) _flatten(responseJson, prefix, 1, fields);
    return {
      ...fields,
      '$prefix.id': '${ids.first}',
      '$prefix.ids': ids.values.join(','),
      '$prefix.count': '${ids.values.length}',
    };
  }

  static void _flatten(Object? value, String name, int depth, Map<String, String> out) {
    if (out.length >= maxFields) return;
    switch (value) {
      case Map():
        if (depth > maxDepth) return;
        for (final entry in value.entries) {
          final key = '${entry.key}';
          if (!_referenceable('$name.$key')) continue;
          _flatten(entry.value, '$name.$key', depth + 1, out);
        }
      case List():
        if (depth > maxDepth) return;
        for (final (i, item) in value.take(maxListItems).indexed) {
          _flatten(item, '$name.$i', depth + 1, out);
        }
      case null:
        return;
      default:
        final text = ResponseReader.stringify(value);
        // A value holding `{{...}}` would be expanded again by the variable resolver, so a response could make the undo
        // request read a variable it never named: such a value is left out.
        if (text.length > maxValueLength || text.contains('{{')) return;
        out[name] = text;
    }
  }

  /// Whether `{{name}}` is a token the variable resolver would substitute.
  static bool _referenceable(String name) {
    final token = '{{$name}}';
    return AppConstants.variablePattern.matchAsPrefix(token)?.end == token.length;
  }
}
