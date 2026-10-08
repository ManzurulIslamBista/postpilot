// Pure Dart (no Flutter): the app and the command line find created ids the same way.
import 'dart:convert';
import '../../../scripting/domain/evaluator/json_path_resolver.dart';

/// The id (or ids) a create request answered with. Each is an `int`, or a `String` for a REST API with text ids.
final class CreatedIds {
  final List<Object> values;

  /// Where they were found, for the person: `the result`, `id`, `data.id`, or the path they chose.
  final String source;

  const CreatedIds(this.values, this.source);

  bool get areNumbers => values.every((v) => v is int);

  Object get first => values.first;
}

/// Finds what a create request made, in its response.
///
/// Odoo JSON-2 answers `create` with the result itself: a list of ids (`[42, 43]`), an id on older versions, or `false`
/// when nothing was made. Odoo 18 and older wrap that in a JSON-RPC envelope whose own `id` is the number of the call,
/// not of the record, so the envelope is read through `result`. A REST API answers with the new record, in which the id
/// is `id`, `data.id` or `result.id`, or with the id alone as `result`. A person can name the path when it is elsewhere.
abstract final class CreatedIdDetector {
  /// The places a REST answer is searched, in order, before `result`.
  static const objectPaths = ['id', 'data.id', 'result.id'];

  /// Most ids taken from one answer: a bulk create of more is almost certainly not meant to be undone one by one.
  static const maxIds = 1000;

  static const _longestTextId = 200;

  /// [fromBody] for a response that is already decoded.
  static CreatedIds? detect(Object? json, {String idPath = ''}) {
    final path = idPath.trim();
    if (path.isNotEmpty) {
      final ids = _idsOf(JsonPathResolver.resolve(json, path), strings: true);
      return ids == null ? null : CreatedIds(ids, path);
    }
    if (json is! Map) {
      final ids = _idsOf(json, strings: false);
      return ids == null ? null : CreatedIds(ids, 'the result');
    }
    if (json.containsKey('jsonrpc')) {
      // An Odoo 18 or older answer: the error, or the result. The envelope's own `id` is never a record.
      if (json['error'] != null) return null;
      final result = json['result'];
      final ids = _idsOf(result, strings: false) ?? (result is Map ? _idsOf(result['id'], strings: false) : null);
      return ids == null ? null : CreatedIds(ids, result is Map ? 'result.id' : 'result');
    }
    for (final candidate in objectPaths) {
      final ids = _idsOf(JsonPathResolver.resolve(json, candidate), strings: true);
      if (ids != null) return CreatedIds(ids, candidate);
    }
    final ids = _idsOf(json['result'], strings: false);
    return ids == null ? null : CreatedIds(ids, 'result');
  }

  /// The ids in a response [body]; null when it is not JSON or names none.
  static CreatedIds? fromBody(String body, {String idPath = ''}) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    return detect(json, idPath: idPath);
  }

  /// Whether [body] is JSON that says nothing was created (Odoo's `false`, `null`, `true`, an empty list): not a
  /// failure to find an id, so the ledger does not complain about it.
  static bool saysNothingWasCreated(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return false;
    }
    if (json is Map && json.containsKey('jsonrpc')) {
      if (json['error'] != null) return true;
      return _nothing(json['result']);
    }
    return _nothing(json);
  }

  static bool _nothing(Object? value) => value == null || value is bool || (value is List && value.isEmpty);

  /// [value] as ids: a positive whole number, a non-empty list of them, a list of records that each have an `id`.
  /// [strings] also accepts text ids (a UUID), which only a REST id may be.
  static List<Object>? _idsOf(Object? value, {required bool strings}) {
    final one = _idOf(value, strings: strings);
    if (one != null) return [one];
    if (value is! List || value.isEmpty || value.length > maxIds) return null;
    final ids = <Object>[];
    for (final item in value) {
      final id = _idOf(item is Map ? item['id'] : item, strings: strings);
      if (id == null) return null;
      ids.add(id);
    }
    return ids;
  }

  static Object? _idOf(Object? value, {required bool strings}) {
    if (value is int) return value > 0 ? value : null;
    // The web build decodes every JSON number as a double.
    if (value is double) return value.isFinite && value > 0 && value == value.truncateToDouble() ? value.toInt() : null;
    if (strings && value is String) {
      final text = value.trim();
      if (text.isEmpty || text.length > _longestTextId || text.contains(RegExp(r'\s'))) return null;
      return int.tryParse(text) ?? text;
    }
    return null;
  }
}
