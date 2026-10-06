import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../entities/baseline_snapshot.dart';
import '../entities/drift_report.dart';
import 'baseline_headers.dart';
import 'baseline_recorder.dart';
import 'field_path.dart';
import 'response_time_bound.dart';

/// Compares a response with a request's baseline and says what changed, and how much each change matters.
///
///  * BREAKING: the status changed class, the body stopped being JSON, a field disappeared, changed type, became
///    null (or, for an array's elements, stopped being in every one), a value of an enumeration no longer appears,
///    or `Content-Type` changed.
///  * NON-BREAKING: the status code changed within its class, a field or an enumeration value is new, a field that
///    was always null has a value, or the response is slower than the baseline's limit.
///  * INFO: an optional field is absent, an array was or is empty so its items could not be compared, a stable value
///    changed, a minor header changed.
///
/// Pure Dart, so the app, the collection runner and the command line judge a response identically.
abstract final class DriftDetector {
  static DriftReport compare(BaselineSnapshot baseline, ApiResponseEntity response) =>
      compareObservation(baseline, ResponseObservation.of(response));

  static DriftReport compareObservation(BaselineSnapshot baseline, ResponseObservation observation) {
    final current = BaselineRecorder.snapshotOf(
      observation,
      volatile: baseline.volatile,
      alwaysValueAt: baseline.values.keys,
    );
    return _Diff(baseline, current, observation).run();
  }
}

final class _Diff {
  final BaselineSnapshot b;
  final BaselineSnapshot c;
  final ResponseObservation obs;
  final List<DriftChange> changes = [];

  /// Paths whose whole subtree was already reported as removed, added or changed, so their children stay quiet.
  final List<String> _skip = [];

  _Diff(this.b, this.c, this.obs);

  void _add(DriftKind kind, String path, String message, {DriftSeverity? severity}) =>
      changes.add(DriftChange(kind: kind, severity: severity ?? kind.severity, path: path, message: message));

  bool _skipped(String path) => _skip.any((s) => FieldPath.isUnder(path, s));

  DriftReport run() {
    if (b.status ~/ 100 != c.status ~/ 100) {
      _add(
        DriftKind.statusClassChanged,
        '',
        'Status changed from ${b.status} to ${c.status} (${_class(b.status)} to ${_class(c.status)}). '
        'The rest of the response is not compared until the status is back in the same class.',
      );
      return DriftReport(changes);
    }
    if (b.status != c.status) {
      _add(DriftKind.statusChanged, '', 'Status changed from ${b.status} to ${c.status}, both ${_class(b.status)}.');
    }
    _headers();
    _body();
    _latency();
    final ordered = [
      for (final severity in DriftSeverity.values)
        for (final change in changes)
          if (change.severity == severity) change,
    ];
    return DriftReport(ordered);
  }

  String _class(int status) => '${status ~/ 100}xx';

  // --- headers -------------------------------------------------------------------

  void _headers() {
    for (final e in b.headers.entries) {
      final now = c.headers[e.key];
      if (now == e.value) continue;
      final name = _headerName(e.key);
      if (e.key == BaselineHeaders.contentType) {
        _add(
          DriftKind.contentTypeChanged,
          e.key,
          now == null ? 'Content-Type is missing; it was ${e.value}.' : 'Content-Type changed from ${e.value} to $now.',
        );
      } else if (now == null) {
        _add(DriftKind.headerChanged, e.key, 'The $name header is gone${e.value == BaselineHeaders.present ? '' : '; it was ${e.value}'}.');
      } else {
        _add(DriftKind.headerChanged, e.key, 'The $name header changed from ${e.value} to $now.');
      }
    }
    for (final e in c.headers.entries) {
      if (b.headers.containsKey(e.key)) continue;
      final name = _headerName(e.key);
      _add(
        DriftKind.headerChanged,
        e.key,
        e.value == BaselineHeaders.present ? 'The response now has a $name header.' : 'The response now has $name: ${e.value}.',
      );
    }
  }

  String _headerName(String lower) => lower.split('-').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join('-');

  // --- body ----------------------------------------------------------------------

  void _body() {
    if (b.isJson && !c.isJson) {
      _add(
        DriftKind.bodyNotJson,
        '',
        obs.parsed.isEmpty ? 'The body is empty now; the baseline had a JSON body.' : 'The body is no longer JSON; the baseline had a JSON body.',
      );
      return;
    }
    if (!b.isJson && c.isJson) {
      _add(DriftKind.bodyNowJson, '', 'The body is JSON now; the baseline body was not.');
      return;
    }
    if (!b.isJson) return;
    _removedAndChanged();
    _added();
    _enums();
    _values();
  }

  void _removedAndChanged() {
    final emptyNow = <String>{};
    for (final e in b.fields.entries) {
      final path = e.key;
      if (_skipped(path)) continue;
      final base = e.value;
      final now = c.fields[path];
      if (now == null) {
        final array = _emptyArrayAbove(path, c);
        if (array != null) {
          if (emptyNow.add(array)) {
            _add(
              DriftKind.elementsUnknown,
              array,
              '${FieldPath.display(array)} is empty now, so the fields of its items were not compared.',
            );
            _skip.add(FieldPath.element(array));
          }
          continue;
        }
        _add(
          base.optional ? DriftKind.optionalFieldAbsent : DriftKind.fieldRemoved,
          path,
          base.optional
              ? '${FieldPath.display(path)} is not in this response (it was only in some items of the baseline).'
              : '${FieldPath.display(path)} was removed.',
        );
        _skip.add(path);
        continue;
      }
      _compareTypes(path, base, now);
      if (!base.optional && now.optional && path.isNotEmpty && !_skipped(path)) {
        _add(
          DriftKind.becameOptional,
          path,
          '${FieldPath.display(path)} is missing from some items now; it was in every one in the baseline.',
        );
      }
    }
  }

  void _compareTypes(String path, BaselineField base, BaselineField now) {
    final added = {
      for (final t in now.types)
        if (!_covered(t, base.types)) t,
    };
    if (added.isEmpty) return;
    final shown = FieldPath.display(path);
    if (base.types.length == 1 && base.types.single == 'null') {
      _add(DriftKind.nullFilled, path, '$shown was always null in the baseline and now has a value (${_types(now.types)}).');
      return;
    }
    if (added.length == 1 && added.single == 'null') {
      final onlyNull = now.types.length == 1;
      _add(
        DriftKind.becameNull,
        path,
        onlyNull ? '$shown is null; the baseline never had null here.' : '$shown is null in some items; the baseline never had null here.',
        severity: base.optional ? DriftSeverity.nonBreaking : DriftSeverity.breaking,
      );
      if (onlyNull) _skip.add(path);
      return;
    }
    _add(DriftKind.typeChanged, path, '$shown changed from ${_types(base.types)} to ${_types(now.types)}.');
    _skip.add(path);
  }

  /// [type] was seen in the baseline, counting a whole number as a kind of number.
  bool _covered(String type, Set<String> baseline) => baseline.contains(type) || (type == 'integer' && baseline.contains('number'));

  String _types(Set<String> types) {
    final sorted = types.toList()..sort();
    if (sorted.remove('null')) sorted.add('null');
    return sorted.join(' or ');
  }

  void _added() {
    final unknown = <String>{};
    for (final e in c.fields.entries) {
      final path = e.key;
      if (b.fields.containsKey(path) || _skipped(path)) continue;
      final array = _emptyArrayAbove(path, b);
      if (array != null) {
        if (unknown.add(array)) {
          _add(
            DriftKind.elementsUnknown,
            array,
            '${FieldPath.display(array)} was empty in the baseline, so the fields of its items have nothing to be compared with.',
          );
          _skip.add(FieldPath.element(array));
        }
        continue;
      }
      _add(DriftKind.fieldAdded, path, '${FieldPath.display(path)} is new (${_types(e.value.types)}).');
      _skip.add(path);
    }
  }

  /// The nearest array above [path] that exists in [snapshot] but has no elements there, so nothing is known
  /// about the fields of its items.
  String? _emptyArrayAbove(String path, BaselineSnapshot snapshot) {
    if (!path.contains('[]')) return null;
    final steps = FieldPath.steps(path);
    for (var i = 0; i < steps.length; i++) {
      if (steps[i] is String) continue;
      final array = FieldPath.join(steps.sublist(0, i));
      final elements = FieldPath.join(steps.sublist(0, i + 1));
      if (snapshot.fields.containsKey(array) && !snapshot.fields.containsKey(elements)) return array;
    }
    return null;
  }

  void _enums() {
    final shape = obs.shape;
    if (shape == null) return;
    for (final e in b.enums.entries) {
      final path = e.key;
      if (_skipped(path) || b.volatile.contains(path)) continue;
      final field = shape[path];
      if (field == null) continue;
      final known = e.value.values;
      final seenNow = field.distinct;
      final shown = FieldPath.display(path);
      // Fewer values in a smaller sample is not a disappearance: only a response with at least as many values counts.
      if (!field.manyDistinct && field.nonNull >= e.value.instances) {
        final gone = [
          for (final v in known)
            if (!seenNow.contains(v)) v,
        ];
        if (gone.isNotEmpty) {
          _add(
            DriftKind.enumValueGone,
            path,
            '${_list(gone)} ${gone.length == 1 ? 'no longer appears' : 'no longer appear'} in $shown; the baseline had ${_list(known)}.',
          );
        }
      }
      final fresh = [
        for (final v in seenNow)
          if (!known.contains(v)) v,
      ];
      if (fresh.isNotEmpty) {
        _add(DriftKind.enumValueAdded, path, '$shown has ${fresh.length == 1 ? 'a new value' : 'new values'}: ${_list(fresh)}.');
      }
    }
  }

  String _list(List<Object> values) {
    final shown = values.take(4).map(_quote).join(', ');
    return values.length > 4 ? '$shown and ${values.length - 4} more' : shown;
  }

  void _values() {
    final shape = obs.shape;
    if (shape == null) return;
    for (final e in b.values.entries) {
      final path = e.key;
      if (_skipped(path) || b.volatile.contains(path)) continue;
      final field = shape[path];
      if (field == null || field.samples.length != 1 || !field.isScalar) continue;
      final now = field.samples.single;
      if (now != e.value) {
        _add(DriftKind.valueChanged, path, '${FieldPath.display(path)} was ${_quote(e.value)}, now ${_quote(now)}.');
      }
    }
  }

  String _quote(Object value) {
    if (value is! String) return '$value';
    final text = value.length > 40 ? '${value.substring(0, 40)}…' : value;
    return '"$text"';
  }

  // --- latency -------------------------------------------------------------------

  void _latency() {
    final limit = ResponseTimeBound.forMeasured(b.timeMs);
    if (c.timeMs > limit) {
      _add(
        DriftKind.slower,
        '',
        'The response took ${c.timeMs} ms; the baseline took ${b.timeMs} ms, and more than $limit ms is reported.',
      );
    }
  }
}
