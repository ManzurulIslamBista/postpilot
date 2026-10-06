// Pure Dart (no Flutter).
import '../domain/entities/odoo_connection.dart';
import '../domain/entities/odoo_model_info.dart';
import '../domain/entities/odoo_result.dart';
import '../domain/services/odoo_error_parser.dart';
import '../domain/services/odoo_json2.dart';

/// Runs one call on a server: [OdooClient.call], or a fake in a test.
typedef OdooCaller = Future<OdooResult> Function(OdooConnection connection, OdooCall call);

/// The answer of a lookup: a value, or why there is none. Never throws for a server that refuses.
final class OdooLookup<T> {
  final T? value;
  final String? error;
  final OdooErrorInfo? info;
  const OdooLookup.ok(T this.value) : error = null, info = null;
  const OdooLookup.failed(String this.error, {this.info}) : value = null;
  bool get ok => error == null;
}

/// A record picked by name: its id and its display name.
final class OdooRecordRef {
  final int id;
  final String name;
  const OdooRecordRef(this.id, this.name);
}

final class OdooModelRef {
  final String model;
  final String label;
  const OdooModelRef(this.model, this.label);
}

/// Reads what the tools of Studio need to know about a server, and remembers it for the session, per server and
/// database: a model's fields (every payload, check and explorer needs them), the list of models, and the answers
/// to the small questions of the forms (a name search, `default_get`, one record, the XML-ID of a record).
///
/// Every call here only reads.
final class OdooSchemaService {
  final OdooCaller _call;
  OdooSchemaService(this._call);

  final Map<String, OdooModelInfo> _fields = {};
  final Map<String, List<OdooModelRef>> _models = {};

  /// What `fields_get` is asked for. `relation_field` is the inverse of a one2many; servers that do not know an
  /// attribute leave it out of the answer.
  static const fieldAttributes = [
    'string', 'type', 'required', 'relation', 'selection', 'readonly', 'store', 'help', 'relation_field',
  ];

  OdooModelInfo? cachedFields(OdooConnection connection, String model) => _fields['${connection.identity}|$model'];

  List<OdooModelRef>? cachedModels(OdooConnection connection) => _models[connection.identity];

  /// Remembers [info], read by something else (the Explorer), so the other tools do not read it again.
  void remember(OdooConnection connection, OdooModelInfo info) => _fields['${connection.identity}|${info.model}'] = info;

  /// Forgets what was read: of one [connection] (a server and database), or of everything.
  void clear({OdooConnection? connection}) {
    if (connection == null) {
      _fields.clear();
      _models.clear();
      return;
    }
    final prefix = '${connection.identity}|';
    _fields.removeWhere((key, _) => key.startsWith(prefix));
    _models.remove(connection.identity);
  }

  OdooLookup<T> _failed<T>(OdooConnection connection, OdooResult r) =>
      OdooLookup.failed(r.failureText(jsonRpc: connection.protocol == OdooProtocol.jsonRpc), info: r.error);

  /// The fields of [model]; from the memory unless [refresh].
  Future<OdooLookup<OdooModelInfo>> fields(OdooConnection connection, String model, {bool refresh = false}) async {
    final name = model.trim();
    final key = '${connection.identity}|$name';
    final known = _fields[key];
    if (known != null && !refresh) return OdooLookup.ok(known);
    final r = await _call(connection, OdooCall(model: name, method: 'fields_get', params: const {'attributes': fieldAttributes}));
    if (!r.ok) return _failed(connection, r);
    final parsed = OdooModelInfo.parse(name, r.body);
    if (parsed == null) return OdooLookup.failed('The server did not return a field list for $name.');
    _fields[key] = parsed;
    return OdooLookup.ok(parsed);
  }

  /// Every model of the server (`ir.model`), by technical name.
  Future<OdooLookup<List<OdooModelRef>>> models(OdooConnection connection, {bool refresh = false}) async {
    final known = _models[connection.identity];
    if (known != null && !refresh) return OdooLookup.ok(known);
    final r = await _call(
      connection,
      const OdooCall(model: 'ir.model', method: 'search_read', params: {'domain': <Object?>[], 'fields': ['model', 'name'], 'order': 'model'}),
    );
    if (!r.ok) return _failed(connection, r);
    final json = r.json;
    if (json is! List) return const OdooLookup.failed('The server did not return a list of models.');
    final models = [
      for (final m in json)
        if (m is Map && m['model'] is String) OdooModelRef(m['model'] as String, '${m['name'] ?? ''}'),
    ];
    _models[connection.identity] = models;
    return OdooLookup.ok(models);
  }

  /// Whether the server has [model]: true or false when it could be told, null when this user may not look
  /// (then the model is judged by reading its fields).
  Future<bool?> modelExists(OdooConnection connection, String model) async {
    final listed = _models[connection.identity];
    if (listed != null) return listed.any((m) => m.model == model);
    final r = await _call(
      connection,
      OdooCall(model: 'ir.model', method: 'search_count', params: {'domain': [['model', '=', model]]}),
    );
    final json = r.json;
    return r.ok && json is int ? json > 0 : null;
  }

  /// The records of [model] whose name contains [text], for a many2one box.
  Future<OdooLookup<List<OdooRecordRef>>> nameSearch(OdooConnection connection, String model, String text, {int limit = 8}) async {
    final r = await _call(
      connection,
      OdooCall(model: model, method: 'name_search', params: {'name': text, 'operator': 'ilike', 'limit': limit}),
    );
    if (!r.ok) return _failed(connection, r);
    final json = r.json;
    if (json is! List) return const OdooLookup.failed('The server did not return a list of records.');
    return OdooLookup.ok([
      for (final pair in json)
        if (pair is List && pair.length >= 2 && pair.first is int) OdooRecordRef(pair.first as int, '${pair[1]}'),
    ]);
  }

  /// The value Odoo would give each of [fields] on a new record of [model].
  Future<OdooLookup<Map<String, Object?>>> defaultGet(OdooConnection connection, String model, List<String> fields) async {
    final r = await _call(connection, OdooCall(model: model, method: 'default_get', params: {'fields_list': fields}));
    if (!r.ok) return _failed(connection, r);
    final json = r.json;
    return json is Map ? OdooLookup.ok(Map<String, Object?>.from(json)) : const OdooLookup.failed('The server did not return default values.');
  }

  /// One record, with only [fields] (an empty list reads them all).
  Future<OdooLookup<Map<String, Object?>>> readRecord(OdooConnection connection, String model, int id, List<String> fields) async {
    final r = await _call(
      connection,
      OdooCall(model: model, method: 'read', ids: [id], params: {if (fields.isNotEmpty) 'fields': fields}),
    );
    if (!r.ok) return _failed(connection, r);
    final json = r.json;
    if (json is List && json.isNotEmpty && json.first is Map) return OdooLookup.ok(Map<String, Object?>.from(json.first as Map));
    return OdooLookup.failed('Record $id of $model does not exist, or this user may not read it.');
  }

  /// The XML-ID (`module.name`) of a record, when it has one and this user may read `ir.model.data`; null otherwise.
  /// A record created by hand has none.
  Future<String?> xmlIdOf(OdooConnection connection, String model, int id) async {
    final r = await _call(
      connection,
      OdooCall(model: 'ir.model.data', method: 'search_read', params: {
        'domain': [['model', '=', model], ['res_id', '=', id]],
        'fields': ['module', 'name'],
        'limit': 5,
      }),
    );
    final json = r.json;
    if (!r.ok || json is! List) return null;
    String? fallback;
    for (final row in json) {
      if (row is! Map || row['module'] is! String || row['name'] is! String) continue;
      final xmlId = '${row['module']}.${row['name']}';
      if (row['module'] != '__export__') return xmlId;
      fallback ??= xmlId;
    }
    return fallback;
  }
}
