import 'body_shape.dart';
import 'field_path.dart';

/// What two responses to the same request say about which values change by themselves.
final class StabilityReport {
  /// Paths whose value was different in the two responses, as `x[].y` column paths (a value that differed in any
  /// element marks the whole column). These must never become "equals" checks.
  final Set<String> changing;

  /// Paths present in one response and missing from the other: optional, so not safe to require.
  final Set<String> unstablePresence;

  /// Arrays that had a different number of elements.
  final Set<String> changingLength;

  /// The two bodies were both JSON, so the comparison means something.
  final bool comparable;

  const StabilityReport({
    this.changing = const {},
    this.unstablePresence = const {},
    this.changingLength = const {},
    this.comparable = true,
  });

  static const notComparable = StabilityReport(comparable: false);

  /// A value at [path] (column form) is the same in both responses.
  bool isStable(String path) => comparable && !changing.contains(path) && !unstablePresence.contains(path);

  bool get isEmpty => changing.isEmpty && unstablePresence.isEmpty && changingLength.isEmpty;

  /// Every path that is not to be trusted, for a baseline to remember as volatile.
  Set<String> get volatilePaths => {...changing, ...unstablePresence};
}

/// Compares two decoded bodies of one request, structurally: same keys, same types, same values, element by element.
abstract final class StabilityProbe {
  static StabilityReport compare(Object? first, Object? second) {
    final run = _Comparison();
    run.walk(first, second, FieldPath.root);
    return StabilityReport(
      changing: run.changing,
      unstablePresence: run.presence,
      changingLength: run.length,
    );
  }
}

final class _Comparison {
  final changing = <String>{};
  final presence = <String>{};
  final length = <String>{};
  int _nodes = 0;

  void walk(Object? a, Object? b, String path) {
    if (_nodes++ >= BodyShape.maxNodes) return;
    if (a is Map && b is Map) {
      for (final key in {...a.keys, ...b.keys}) {
        final child = FieldPath.child(path, '$key');
        if (child == null) continue;
        final inA = a.containsKey(key);
        final inB = b.containsKey(key);
        if (inA && inB) {
          walk(a[key], b[key], child);
        } else {
          presence.add(child);
        }
      }
    } else if (a is List && b is List) {
      if (a.length != b.length) length.add(path);
      final column = FieldPath.element(path);
      final common = a.length < b.length ? a.length : b.length;
      for (var i = 0; i < common && i < BodyShape.maxArrayItems; i++) {
        walk(a[i], b[i], column);
      }
    } else if (a != b) {
      changing.add(path);
    }
  }
}
