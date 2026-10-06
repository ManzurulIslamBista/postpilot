import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../entities/baseline_snapshot.dart';
import '../entities/drift_report.dart';
import 'baseline_recorder.dart';
import 'field_path.dart';

/// "Accept change": makes a baseline agree with a response about the changes the person chose to accept, and
/// about nothing else. After accepting every change of a report, the same response shows no drift.
abstract final class DriftAccept {
  /// [baseline] with [changes] taken over from [response]; changes not listed stay as drift.
  static BaselineSnapshot apply(BaselineSnapshot baseline, ApiResponseEntity response, Iterable<DriftChange> changes) =>
      applyObservation(baseline, ResponseObservation.of(response), changes);

  static BaselineSnapshot applyObservation(BaselineSnapshot baseline, ResponseObservation observation, Iterable<DriftChange> changes) {
    final now = BaselineRecorder.snapshotOf(
      observation,
      volatile: baseline.volatile,
      alwaysValueAt: baseline.values.keys,
    );
    var result = baseline;
    for (final change in changes) {
      result = _take(result, now, change);
    }
    return result;
  }

  static BaselineSnapshot _take(BaselineSnapshot base, BaselineSnapshot now, DriftChange change) {
    final path = change.path;
    switch (change.kind) {
      case DriftKind.statusClassChanged:
        // The body was not compared while the status was in another class: taking the new status takes the lot.
        return now.copyWith(volatile: base.volatile);
      case DriftKind.statusChanged:
        return base.copyWith(status: now.status);
      case DriftKind.bodyNotJson:
      case DriftKind.bodyNowJson:
        return base.copyWith(
          isJson: now.isJson,
          fields: now.fields,
          enums: now.enums,
          values: now.values,
          shapeTruncated: now.shapeTruncated,
        );
      case DriftKind.fieldRemoved:
      case DriftKind.fieldAdded:
      case DriftKind.typeChanged:
      case DriftKind.becameNull:
      case DriftKind.nullFilled:
      case DriftKind.becameOptional:
      case DriftKind.optionalFieldAbsent:
      case DriftKind.elementsUnknown:
        return base.copyWith(
          fields: _subtree(base.fields, now.fields, path),
          enums: _subtree(base.enums, now.enums, path),
          values: _subtree(base.values, now.values, path),
        );
      case DriftKind.enumValueGone:
      case DriftKind.enumValueAdded:
        return base.copyWith(enums: _entry(base.enums, now.enums, path));
      case DriftKind.valueChanged:
        return base.copyWith(values: _entry(base.values, now.values, path));
      case DriftKind.contentTypeChanged:
      case DriftKind.headerChanged:
        return base.copyWith(headers: _entry(base.headers, now.headers, path));
      case DriftKind.slower:
        return base.copyWith(timeMs: now.timeMs);
    }
  }

  /// [from] with the entry at [key] replaced by the one in [to], or removed when [to] has none.
  static Map<String, V> _entry<V>(Map<String, V> from, Map<String, V> to, String key) {
    final out = {...from};
    final replacement = to[key];
    if (replacement == null) {
      out.remove(key);
    } else {
      out[key] = replacement;
    }
    return out;
  }

  /// [from] with everything at [path] or below it replaced by what [to] has there.
  static Map<String, V> _subtree<V>(Map<String, V> from, Map<String, V> to, String path) => {
        for (final e in from.entries)
          if (!FieldPath.isUnder(e.key, path)) e.key: e.value,
        for (final e in to.entries)
          if (FieldPath.isUnder(e.key, path)) e.key: e.value,
      };
}
