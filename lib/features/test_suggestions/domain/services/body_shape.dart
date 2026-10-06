import 'field_path.dart';

/// What was seen at one path of a JSON body, over every value found there (all the elements of an array count).
final class FieldShape {
  /// `integer`, `number`, `string`, `boolean`, `object`, `array` or `null`. A whole-valued double counts as an
  /// integer, the way the schema validator reads it, so `100` and `100.0` are one type.
  final Set<String> types;

  /// How many values were found at the path.
  final int seen;

  /// How many of them were not JSON null.
  final int nonNull;

  /// How many objects (or, for an element, arrays) could have held it; `seen` below this means it is optional.
  final int parents;

  /// The non-null scalar values, in document order, up to [BodyShape.maxSamples].
  final List<Object> samples;

  /// Distinct non-null scalar values in order of first appearance, up to [BodyShape.maxDistinct] + 1 of them (so
  /// "more than that many" is known without keeping them all).
  final List<Object> distinct;

  const FieldShape({
    required this.types,
    required this.seen,
    required this.nonNull,
    required this.parents,
    required this.samples,
    required this.distinct,
  });

  bool get nullable => types.contains('null');

  int get distinctCount => distinct.length;

  /// More distinct values than [BodyShape.maxDistinct]: not a small set.
  bool get manyDistinct => distinct.length > BodyShape.maxDistinct;

  /// Present in some of the places it could be and absent in others.
  bool get optional => parents > 0 && seen < parents;

  /// Every value here is a string, number or boolean (null aside).
  bool get isScalar => types.isNotEmpty && types.every(_scalarTypes.contains);

  /// The type a lone-typed field has, ignoring null; null when it has several kinds of value.
  String? get soleType {
    final real = types.where((t) => t != 'null');
    return real.length == 1 ? real.single : null;
  }

  static const _scalarTypes = {'integer', 'number', 'string', 'boolean', 'null'};
}

/// The structure of a decoded JSON body: every path, its types, how often it appears and a few of its values.
/// Shared by test suggestions (what to assert), baselines (what to remember) and drift detection (what changed).
final class BodyShape {
  /// Values looked at before the walk stops, so a huge body costs a bounded amount of time.
  static const maxNodes = 100000;

  /// Elements looked at in one array.
  static const maxArrayItems = 500;
  static const maxSamples = 30;
  static const maxDistinct = 10;

  /// By path, in the order each path first appeared in the document.
  final Map<String, FieldShape> fields;

  /// The walk stopped at a limit, so [fields] covers only the first part of the body.
  final bool truncated;

  const BodyShape(this.fields, {this.truncated = false});

  FieldShape? operator [](String path) => fields[path];

  /// An array whose elements were looked at has the path `x[]`; an empty array has none, so its element shape is unknown.
  bool hasElements(String arrayPath) => fields.containsKey(FieldPath.element(arrayPath));

  /// Paths directly below [path]: its keys, or `path[]` for an array.
  Iterable<String> childrenOf(String path) sync* {
    final depth = FieldPath.depth(path);
    for (final other in fields.keys) {
      if (other.length > path.length && other.startsWith(path) && FieldPath.depth(other) == depth + 1) {
        if (path.isEmpty || other[path.length] == '.' || other[path.length] == '[') yield other;
      }
    }
  }

  static BodyShape of(Object? json) {
    final walker = _Walker();
    walker.walk(json, FieldPath.root, null, isElement: false);
    return walker.finish();
  }

  /// The JSON type name of a decoded value.
  static String typeOf(Object? value) => switch (value) {
        null => 'null',
        bool _ => 'boolean',
        int _ => 'integer',
        double d when d.isFinite && d == d.truncateToDouble() => 'integer',
        num _ => 'number',
        String _ => 'string',
        List<dynamic> _ => 'array',
        Map<dynamic, dynamic> _ => 'object',
        _ => 'unknown',
      };
}

final class _Builder {
  final String path;
  final String? parent;
  final bool isElement;
  final types = <String>{};
  final samples = <Object>[];
  final distinct = <Object>[];
  int seen = 0;
  int nonNull = 0;

  _Builder(this.path, this.parent, this.isElement);
}

final class _Walker {
  final _builders = <String, _Builder>{};

  /// How many times each path held an object (what its keys are "optional" against) or an array.
  final _containerVisits = <String, int>{};
  int _nodes = 0;
  bool _truncated = false;

  void walk(Object? value, String path, String? parent, {required bool isElement}) {
    if (_nodes >= BodyShape.maxNodes) {
      _truncated = true;
      return;
    }
    _nodes++;
    final builder = _builders.putIfAbsent(path, () => _Builder(path, parent, isElement));
    builder.seen++;
    if (value != null) builder.nonNull++;
    final type = BodyShape.typeOf(value);
    builder.types.add(type);
    switch (value) {
      case Map<dynamic, dynamic> map:
        _containerVisits[path] = (_containerVisits[path] ?? 0) + 1;
        for (final entry in map.entries) {
          final child = FieldPath.child(path, '${entry.key}');
          if (child != null) walk(entry.value, child, path, isElement: false);
        }
      case List<dynamic> list:
        _containerVisits[path] = (_containerVisits[path] ?? 0) + 1;
        if (list.length > BodyShape.maxArrayItems) _truncated = true;
        final column = FieldPath.element(path);
        for (var i = 0; i < list.length && i < BodyShape.maxArrayItems; i++) {
          walk(list[i], column, path, isElement: true);
        }
      case null:
        break;
      case Object scalar:
        if (builder.samples.length < BodyShape.maxSamples) builder.samples.add(scalar);
        if (builder.distinct.length <= BodyShape.maxDistinct && !builder.distinct.contains(scalar)) {
          builder.distinct.add(scalar);
        }
    }
  }

  BodyShape finish() => BodyShape(
        {
          for (final b in _builders.values)
            b.path: FieldShape(
              types: Set.unmodifiable(b.types),
              seen: b.seen,
              nonNull: b.nonNull,
              parents: b.isElement || b.parent == null ? 0 : _containerVisits[b.parent] ?? 0,
              samples: List.unmodifiable(b.samples),
              distinct: List.unmodifiable(b.distinct),
            ),
        },
        truncated: _truncated,
      );
}
