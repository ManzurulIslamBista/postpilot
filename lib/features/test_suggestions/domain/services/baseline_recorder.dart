import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../entities/baseline_snapshot.dart';
import 'baseline_headers.dart';
import 'body_shape.dart';
import 'enum_rules.dart';
import 'field_path.dart';
import 'parsed_response.dart';
import 'stability_probe.dart';
import 'volatility.dart';

/// A response read once for baselining and drift detection: status, the headers worth keeping, the body's shape
/// and how long it took.
final class ResponseObservation {
  final ParsedResponse parsed;

  /// The shape of the body; null when it is not JSON.
  final BodyShape? shape;

  /// [BaselineHeaders.of] the response's headers.
  final Map<String, String> headers;

  const ResponseObservation._(this.parsed, this.shape, this.headers);

  factory ResponseObservation.of(ApiResponseEntity response) {
    final parsed = ParsedResponse.of(response);
    return ResponseObservation._(
      parsed,
      parsed.isJson ? BodyShape.of(parsed.json) : null,
      BaselineHeaders.of(response.headers),
    );
  }

  int get status => parsed.status;
  int get timeMs => parsed.timeMs;
  bool get isJson => parsed.isJson;
}

/// Turns a response into a [BaselineSnapshot].
abstract final class BaselineRecorder {
  /// Paths remembered at most; a wider body is described by its first paths and flagged.
  static const maxPaths = 2000;

  /// A string value longer than this is not kept: it is content, not contract.
  static const maxValueChars = 200;

  /// The snapshot of [response]. [stability] (from a second response) adds the paths that change by themselves
  /// to [volatile]; whatever is in [volatile] already (a previous baseline's) stays.
  static BaselineSnapshot record(ApiResponseEntity response, {StabilityReport? stability, Set<String> volatile = const {}}) =>
      snapshotOf(ResponseObservation.of(response), volatile: {...volatile, ...?stability?.volatilePaths});

  /// The snapshot of [observation]. Values and value sets are not kept for the paths in [volatile]; a path in
  /// [alwaysValueAt] keeps its value even when it looks like something that changes (the value was judged
  /// stable when the baseline was made).
  static BaselineSnapshot snapshotOf(
    ResponseObservation observation, {
    Set<String> volatile = const {},
    Iterable<String> alwaysValueAt = const [],
  }) {
    final always = alwaysValueAt.toSet();
    final fields = <String, BaselineField>{};
    final enums = <String, BaselineEnum>{};
    final values = <String, Object>{};
    var truncated = observation.shape?.truncated ?? false;
    final shape = observation.shape;
    if (shape != null) {
      for (final entry in shape.fields.entries) {
        if (fields.length >= maxPaths) {
          truncated = true;
          break;
        }
        final path = entry.key;
        final field = entry.value;
        fields[path] = BaselineField(field.types, optional: field.optional);
        if (volatile.contains(path)) continue;
        final set = EnumRules.valuesOf(path, field);
        if (set != null) enums[path] = BaselineEnum(set, field.nonNull);
        final value = _stableValue(path, field, forced: always.contains(path));
        if (value != null) values[path] = value;
      }
    }
    return BaselineSnapshot(
      status: observation.status,
      headers: observation.headers,
      isJson: observation.isJson,
      fields: fields,
      enums: enums,
      values: values,
      volatile: volatile,
      timeMs: observation.timeMs,
      shapeTruncated: truncated,
    );
  }

  /// The value of a scalar outside any array that is expected to stay the same, or null.
  static Object? _stableValue(String path, FieldShape field, {required bool forced}) {
    if (path.isEmpty || field.seen != 1 || field.samples.length != 1 || field.soleType == null || !field.isScalar) return null;
    if (path.contains('[') && FieldPath.crossesArray(path)) return null;
    final value = field.samples.single;
    if (value is String && value.length > maxValueChars) return null;
    if (value is num && (!value.isFinite || value.abs() >= 9007199254740992)) return null;
    if (!forced && Volatility.reasonAt(path, value) != null) return null;
    return value;
  }
}
