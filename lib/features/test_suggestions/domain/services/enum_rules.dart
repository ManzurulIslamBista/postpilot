import 'body_shape.dart';
import 'field_path.dart';
import 'volatility.dart';

/// Decides which fields of a body behave like an enumeration: a few values repeated many times (`status`,
/// `role`, `type`), as opposed to free text or data that happens to repeat.
abstract final class EnumRules {
  /// A value set is only believed after this many values were seen, ...
  static const minInstances = 4;

  /// ... with at most this many different ones, ...
  static const maxValues = 5;

  /// Words that make a whole-number field a code rather than a quantity.
  static const _codeWords = {'status', 'type', 'state', 'kind', 'level', 'priority', 'role', 'category', 'mode', 'stage', 'phase', 'tier'};

  /// The values of the enumeration at [path], or null when the field does not look like one: too few values seen,
  /// too many kinds, values that rarely repeat, or a name or content of something that changes by itself.
  static List<Object>? valuesOf(String path, FieldShape field) {
    if (field.nonNull < minInstances || field.distinct.isEmpty || field.manyDistinct) return null;
    if (field.distinct.length > maxValues) return null;
    // Every value repeated at least twice on average: otherwise they are just unrelated values.
    if (field.distinct.length * 2 > field.nonNull) return null;
    final kinds = field.types.where((t) => t != 'null').toSet();
    final textual = kinds.length == 1 && kinds.single == 'string';
    final code = kinds.length == 1 && kinds.single == 'integer' && Volatility.words(FieldPath.lastKey(path)).any(_codeWords.contains);
    if (!textual && !code) return null;
    for (final value in field.distinct) {
      if (value is String && value.length > 40) return null;
    }
    if (Volatility.reasonAt(path, null) != null) return null;
    if (field.distinct.any((v) => Volatility.reasonAt('', v) != null)) return null;
    return field.distinct;
  }
}
