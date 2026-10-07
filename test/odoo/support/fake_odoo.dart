// An in-process Odoo server for tests: the JSON-2 API (Odoo 19), the JSON-RPC session and `call_kw` (Odoo 18 and older),
// with a realistic subset of res.partner. It is written from how Odoo behaves, not from PostPilot's code: the call_kw
// side takes positional arguments the way Odoo's signatures do, so a wrong mapping in the app shows up as a failure here.
import 'dart:convert';
import 'package:postpilot/core/network/api_client.dart';
import 'package:postpilot/core/network/api_http_response.dart';

/// `fields_get` of res.partner, reduced.
const partnerFields = <String, Map<String, Object?>>{
  'id': {'type': 'integer', 'string': 'ID', 'readonly': true, 'store': true},
  'display_name': {'type': 'char', 'string': 'Display Name', 'readonly': true, 'store': false},
  'name': {'type': 'char', 'string': 'Name', 'required': true, 'store': true},
  'complete_name': {'type': 'char', 'string': 'Complete Name', 'readonly': true, 'store': true},
  'email': {'type': 'char', 'string': 'Email', 'store': true},
  'phone': {'type': 'char', 'string': 'Phone', 'store': true},
  'comment': {'type': 'html', 'string': 'Notes', 'store': true},
  'is_company': {'type': 'boolean', 'string': 'Is a Company', 'store': true},
  'active': {'type': 'boolean', 'string': 'Active', 'store': true},
  'type': {
    'type': 'selection',
    'string': 'Address Type',
    'selection': [
      ['contact', 'Contact'],
      ['invoice', 'Invoice Address'],
      ['delivery', 'Delivery Address'],
      ['other', 'Other Address'],
    ],
    'store': true,
  },
  'color': {'type': 'integer', 'string': 'Color Index', 'store': true},
  'credit_limit': {'type': 'float', 'string': 'Credit Limit', 'store': true},
  'date': {'type': 'date', 'string': 'Date', 'store': true},
  'create_date': {'type': 'datetime', 'string': 'Created on', 'readonly': true, 'store': true},
  'write_date': {'type': 'datetime', 'string': 'Last Updated on', 'readonly': true, 'store': true},
  'parent_id': {'type': 'many2one', 'string': 'Related Company', 'relation': 'res.partner', 'store': true},
  'child_ids': {'type': 'one2many', 'string': 'Contact', 'relation': 'res.partner', 'relation_field': 'parent_id', 'store': true},
  'category_id': {'type': 'many2many', 'string': 'Tags', 'relation': 'res.partner.category', 'store': true},
  'country_id': {'type': 'many2one', 'string': 'Country', 'relation': 'res.country', 'store': true},
  'user_id': {'type': 'many2one', 'string': 'Salesperson', 'relation': 'res.users', 'store': true},
  'commercial_partner_id': {'type': 'many2one', 'string': 'Commercial Entity', 'relation': 'res.partner', 'readonly': true, 'store': true},
  'partner_share': {'type': 'boolean', 'string': 'Share Partner', 'readonly': true, 'store': false},
  'image_1920': {'type': 'binary', 'string': 'Image', 'store': true},
};

const countryFields = <String, Map<String, Object?>>{
  'id': {'type': 'integer', 'string': 'ID', 'readonly': true, 'store': true},
  'name': {'type': 'char', 'string': 'Country Name', 'required': true, 'store': true},
  'code': {'type': 'char', 'string': 'Country Code', 'store': true},
};

const categoryFields = <String, Map<String, Object?>>{
  'id': {'type': 'integer', 'string': 'ID', 'readonly': true, 'store': true},
  'name': {'type': 'char', 'string': 'Tag Name', 'required': true, 'store': true},
};

class _OdooError implements Exception {
  final int status;
  final String name;
  final String message;
  _OdooError(this.status, this.name, this.message);
}

/// The Odoo that answers [FakeOdoo.host]. Every request is kept in [requests]; every model method in [calls].
class FakeOdoo implements ApiClient {
  final String host;
  final String apiKey;
  final String login;
  final String password;
  final String db;
  final int uid;

  FakeOdoo({this.host = 'https://odoo.test', this.apiKey = 'key-123', this.login = 'admin', this.password = 'pw-456', this.db = 'prod', this.uid = 2}) {
    fields['res.partner'] = {for (final e in partnerFields.entries) e.key: Map<String, Object?>.of(e.value)};
    fields['res.country'] = {for (final e in countryFields.entries) e.key: Map<String, Object?>.of(e.value)};
    fields['res.partner.category'] = {for (final e in categoryFields.entries) e.key: Map<String, Object?>.of(e.value)};
    records['res.partner'] = [
      {'id': 1, 'name': 'My Company', 'is_company': true, 'active': true, 'type': 'contact', 'email': 'info@example.com', 'parent_id': false, 'child_ids': <int>[], 'category_id': <int>[], 'country_id': 233, 'user_id': false, 'credit_limit': 0.0, 'color': 0},
      {'id': 2, 'name': 'Azure Interior', 'is_company': true, 'active': true, 'type': 'contact', 'email': 'azure@example.com', 'parent_id': false, 'child_ids': [4], 'category_id': [1], 'country_id': 233, 'user_id': false, 'credit_limit': 1500.5, 'color': 3},
      {'id': 3, 'name': 'Deco Addict', 'is_company': true, 'active': true, 'type': 'contact', 'email': false, 'parent_id': false, 'child_ids': <int>[], 'category_id': <int>[], 'country_id': 20, 'user_id': false, 'credit_limit': 0.0, 'color': 0},
      {'id': 4, 'name': 'Brandon Freeman', 'is_company': false, 'active': true, 'type': 'contact', 'email': 'brandon@example.com', 'parent_id': 2, 'child_ids': <int>[], 'category_id': <int>[], 'country_id': false, 'user_id': false, 'credit_limit': 0.0, 'color': 0},
    ];
    records['res.country'] = [
      {'id': 20, 'name': 'Bangladesh', 'code': 'BD'},
      {'id': 233, 'name': 'United States', 'code': 'US'},
    ];
    records['res.partner.category'] = [
      {'id': 1, 'name': 'Vendor'},
      {'id': 2, 'name': 'Prospects'},
    ];
    records['ir.model'] = [
      {'id': 1, 'model': 'res.partner', 'name': 'Contact'},
      {'id': 2, 'model': 'res.country', 'name': 'Country'},
      {'id': 3, 'model': 'res.partner.category', 'name': 'Contact Tag'},
      {'id': 4, 'model': 'sale.order', 'name': 'Sales Order'},
    ];
    records['ir.model.data'] = [
      {'id': 1, 'module': 'base', 'name': 'main_partner', 'model': 'res.partner', 'res_id': 1},
      {'id': 2, 'module': 'base', 'name': 'bd', 'model': 'res.country', 'res_id': 20},
      {'id': 3, 'module': 'base', 'name': 'us', 'model': 'res.country', 'res_id': 233},
      {'id': 4, 'module': 'base', 'name': 'res_partner_category_1', 'model': 'res.partner.category', 'res_id': 1},
      {'id': 5, 'module': '__export__', 'name': 'res_partner_2_abc', 'model': 'res.partner', 'res_id': 2},
    ];
    defaults['res.partner'] = {'active': true, 'type': 'contact', 'lang': 'en_US', 'is_company': false, 'color': 0};
  }

  final Map<String, Map<String, Map<String, Object?>>> fields = {};
  final Map<String, List<Map<String, Object?>>> records = {};
  final Map<String, Map<String, Object?>> defaults = {};

  /// Models the user may not touch at all (every method answers an AccessError), and single `model.method` pairs.
  final Set<String> deniedModels = {};
  final Set<String> deniedMethods = {};

  /// Whether `/web/database/list` answers; Odoo switches it off with `list_db = False`.
  bool listsDatabases = true;
  List<String> databases = ['prod'];

  final List<ApiRequestSpec> requests = [];

  /// `res.partner.create`, `ir.model.data.search_read`...: every model method that ran, in order.
  final List<String> calls = [];
  int authenticateCount = 0;
  final Set<String> _sessions = {};
  int _nextSession = 1;

  /// Makes every open session unknown to the server, as if it had timed out.
  void expireSessions() => _sessions.clear();

  /// The model methods that change data.
  static const writeMethods = {'create', 'write', 'unlink', 'copy'};
  Iterable<String> get writes => calls.where((c) => writeMethods.contains(c.split('.').last));

  // ------------------------------------------------------------------------------------------------------------------

  @override
  Future<ApiHttpResponse> send(ApiRequestSpec spec) async {
    requests.add(spec);
    final uri = Uri.parse(spec.url);
    if ('${uri.scheme}://${uri.authority}' != host) {
      throw StateError('FakeOdoo answers $host, not ${spec.url}');
    }
    final text = spec.body is List<int> ? utf8.decode(spec.body as List<int>) : '';
    final Object? json = text.isEmpty ? null : jsonDecode(text);
    final body = json is Map ? Map<String, Object?>.from(json) : <String, Object?>{};
    final path = uri.path;

    if (path.startsWith('/json/2/')) return _json2(spec, uri, body);
    if (path == '/web/session/authenticate') return _authenticate(body);
    if (path == '/web/database/list') return _databaseList(body);
    if (path.startsWith('/web/dataset/call_kw')) return _callKw(spec, uri, body);
    return _http(404, {'name': 'werkzeug.exceptions.NotFound', 'message': '404 Not Found', 'arguments': [], 'debug': ''});
  }

  ApiHttpResponse _http(int status, Object? json, {List<String> cookies = const []}) => ApiHttpResponse(
        statusCode: status,
        statusMessage: status == 200 ? 'OK' : 'Error',
        headers: {'content-type': 'application/json', if (cookies.isNotEmpty) 'set-cookie': cookies.join(', ')},
        bodyBytes: utf8.encode(jsonEncode(json)),
        duration: Duration.zero,
        setCookies: cookies,
      );

  // --- JSON-2 ---------------------------------------------------------------------------------------------------

  ApiHttpResponse _json2(ApiRequestSpec spec, Uri uri, Map<String, Object?> body) {
    if (spec.headers['Authorization'] != 'bearer $apiKey') {
      return _http(401, {'name': 'werkzeug.exceptions.Unauthorized', 'message': 'Invalid apikey', 'arguments': ['Invalid apikey', 401], 'context': {}, 'debug': 'Traceback (most recent call last):\n  File "/odoo/http.py", line 1, in x\nUnauthorized: 401'});
    }
    final segments = uri.pathSegments; // json, 2, model, method
    final model = segments[2];
    final method = segments[3];
    try {
      final named = Map<String, Object?>.of(body);
      final ids = named.remove('ids');
      named.remove('context');
      final result = _dispatch(model, method, ids is List ? [for (final i in ids) i as int] : const [], named);
      return _http(200, result);
    } on _OdooError catch (e) {
      // JSON-2 answers an error with an HTTP error status; 200 is only what call_kw's envelope uses.
      return _http(e.status == 200 ? 422 : e.status, {'name': e.name, 'message': e.message, 'arguments': [e.message], 'context': {}, 'debug': 'Traceback (most recent call last):\n  File "/odoo/models.py", line 1, in x\n${e.name}: ${e.message}'});
    }
  }

  // --- JSON-RPC -------------------------------------------------------------------------------------------------

  ApiHttpResponse _rpc(Object? id, {Object? result, _OdooError? error}) => _http(
        200,
        error == null
            ? {'jsonrpc': '2.0', 'id': id, 'result': result}
            : {
                'jsonrpc': '2.0',
                'id': id,
                'error': {
                  'code': error.name.endsWith('SessionExpiredException') ? 100 : 200,
                  'message': error.name.endsWith('SessionExpiredException') ? 'Odoo Session Expired' : 'Odoo Server Error',
                  'data': {'name': error.name, 'debug': 'Traceback (most recent call last):\n${error.name}: ${error.message}', 'message': error.message, 'arguments': [error.message], 'context': {}},
                },
              },
      );

  ApiHttpResponse _authenticate(Map<String, Object?> body) {
    authenticateCount++;
    final params = body['params'] is Map ? Map<String, Object?>.from(body['params'] as Map) : <String, Object?>{};
    if (params['db'] != db || params['login'] != login || params['password'] != password) {
      return _rpc(body['id'], error: _OdooError(200, 'odoo.exceptions.AccessDenied', 'Access Denied'));
    }
    final token = 'sess${_nextSession++}';
    _sessions.add(token);
    return _http(
      200,
      {
        'jsonrpc': '2.0',
        'id': body['id'],
        'result': {
          'uid': uid,
          'username': login,
          'name': 'Mitchell Admin',
          'db': db,
          'server_version': '17.0',
          'user_context': {'lang': 'en_US', 'tz': 'Europe/Brussels', 'uid': uid},
        },
      },
      cookies: ['session_id=$token; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Max-Age=604800; HttpOnly; Path=/; SameSite=Lax', 'frontend_lang=en_US; Path=/'],
    );
  }

  ApiHttpResponse _databaseList(Map<String, Object?> body) {
    if (!listsDatabases) return _rpc(body['id'], error: _OdooError(200, 'odoo.exceptions.AccessDenied', 'Database listing is disabled by the administrator'));
    return _rpc(body['id'], result: databases);
  }

  /// Positional parameter names of the methods, as Odoo 17 declares them; `ids` first for the recordset methods.
  static const _positional = <String, List<String>>{
    'search_read': ['domain', 'fields', 'offset', 'limit', 'order'],
    'search_count': ['domain', 'limit'],
    'search': ['domain', 'offset', 'limit', 'order'],
    'read': ['fields', 'load'],
    'create': ['vals_list'],
    'write': ['vals'],
    'unlink': [],
    'exists': [],
    'fields_get': ['allfields', 'attributes'],
    'name_search': ['name', 'args', 'operator', 'limit'],
    'default_get': ['fields_list'],
    'check_object_reference': ['module', 'xml_id', 'raise_on_access_error'],
    'context_get': [],
  };
  static const _onRecords = {'read', 'write', 'unlink', 'exists'};

  ApiHttpResponse _callKw(ApiRequestSpec spec, Uri uri, Map<String, Object?> body) {
    final params = body['params'] is Map ? Map<String, Object?>.from(body['params'] as Map) : <String, Object?>{};
    final cookie = spec.headers['Cookie'] ?? '';
    final token = RegExp(r'session_id=([^;\s]+)').firstMatch(cookie)?[1];
    if (token == null || !_sessions.contains(token)) {
      return _rpc(body['id'], error: _OdooError(200, 'odoo.http.SessionExpiredException', 'Session expired'));
    }
    final model = params['model'] as String;
    final method = params['method'] as String;
    final args = params['args'] is List ? List<Object?>.of(params['args'] as List) : <Object?>[];
    final kwargs = params['kwargs'] is Map ? Map<String, Object?>.of((params['kwargs'] as Map).cast<String, Object?>()) : <String, Object?>{};
    try {
      var ids = const <int>[];
      if (_onRecords.contains(method)) {
        if (args.isEmpty) throw _OdooError(200, 'builtins.TypeError', '$method() missing 1 required positional argument: \'self\'');
        ids = [for (final i in args.removeAt(0) as List) i as int];
      }
      final names = _positional[method];
      if (names == null) throw _OdooError(200, 'odoo.exceptions.UserError', 'Unknown method $model.$method');
      final named = <String, Object?>{};
      for (var i = 0; i < args.length; i++) {
        if (i >= names.length) throw _OdooError(200, 'builtins.TypeError', '$method() takes ${names.length} positional arguments but ${args.length + 1} were given');
        named[names[i]] = args[i];
      }
      kwargs.forEach((k, v) {
        if (named.containsKey(k)) throw _OdooError(200, 'builtins.TypeError', "$method() got multiple values for argument '$k'");
        named[k] = v;
      });
      // name_search's domain is called `args` up to Odoo 18.
      if (method == 'name_search' && named.containsKey('args')) named['domain'] = named.remove('args');
      named.remove('context');
      final result = _dispatch(model, method, ids, named);
      return _rpc(body['id'], result: result);
    } on _OdooError catch (e) {
      return _rpc(body['id'], error: e);
    }
  }

  // --- the models -----------------------------------------------------------------------------------------------

  Object? _dispatch(String model, String method, List<int> ids, Map<String, Object?> named) {
    calls.add('$model.$method');
    if (deniedModels.contains(model) || deniedMethods.contains('$model.$method')) {
      final label = {'res.partner': 'Contact', 'ir.model.data': 'External Identifiers', 'ir.model.access': 'Access'}[model] ?? model;
      throw _OdooError(
        403,
        'odoo.exceptions.AccessError',
        "You are not allowed to access '$label' ($model) records.\n\nThis operation is allowed for the following groups:\n\t- Administration/Settings\n\nContact your administrator to request access if necessary.",
      );
    }
    if (model == 'res.users' && method == 'context_get') return {'lang': 'en_US', 'tz': 'Europe/Brussels'};
    if (method == 'check_object_reference') {
      final row = _rows('ir.model.data').where((r) => r['module'] == named['module'] && r['name'] == named['xml_id']).firstOrNull;
      if (row == null) throw _OdooError(200, 'builtins.ValueError', 'External ID not found in the system: ${named['module']}.${named['xml_id']}');
      return [row['model'], row['res_id']];
    }
    if (method == 'fields_get') {
      final f = fields[model];
      if (f == null) throw _OdooError(404, 'werkzeug.exceptions.NotFound', "Model '$model' does not exist");
      final wanted = named['attributes'] is List ? (named['attributes'] as List).cast<String>().toSet() : null;
      return {
        for (final e in f.entries) e.key: {for (final a in e.value.entries) if (wanted == null || wanted.contains(a.key)) a.key: a.value},
      };
    }
    if (!records.containsKey(model)) throw _OdooError(404, 'werkzeug.exceptions.NotFound', "Model '$model' does not exist");
    final rows = _rows(model);
    switch (method) {
      case 'search_count':
        return _filter(rows, named['domain']).length;
      case 'search':
        return [for (final r in _page(_filter(rows, named['domain']), named)) r['id']];
      case 'search_read':
        return [for (final r in _page(_filter(rows, named['domain']), named)) _read(model, r, named['fields'])];
      case 'read':
        for (final id in ids) {
          if (!rows.any((r) => r['id'] == id)) _missing(model, id);
        }
        return [for (final id in ids) _read(model, rows.firstWhere((r) => r['id'] == id), named['fields'])];
      case 'exists':
        return [for (final id in ids) if (rows.any((r) => r['id'] == id)) id];
      case 'name_search':
        final name = '${named['name'] ?? ''}'.toLowerCase();
        final exact = named['operator'] == '=';
        final hits = [for (final r in rows) if (r['name'] != null && (exact ? '${r['name']}'.toLowerCase() == name : '${r['name']}'.toLowerCase().contains(name)) || (model == 'res.country' && exact && '${r['code']}'.toLowerCase() == name)) r];
        final limit = named['limit'] is int ? named['limit'] as int : 100;
        return [for (final r in hits.take(limit)) [r['id'], r['name']]];
      case 'default_get':
        final wanted = (named['fields_list'] as List? ?? const []).cast<String>();
        return {for (final e in (defaults[model] ?? const {}).entries) if (wanted.contains(e.key)) e.key: e.value};
      case 'create':
        final list = named['vals_list'];
        final created = <int>[];
        for (final vals in (list is List ? list : [list])) {
          created.add(_create(model, Map<String, Object?>.from(vals as Map)));
        }
        return list is List ? created : created.single;
      case 'write':
        for (final id in ids) {
          if (!rows.any((r) => r['id'] == id)) _missing(model, id);
        }
        for (final r in rows.where((r) => ids.contains(r['id']))) {
          r.addAll(Map<String, Object?>.from(named['vals'] as Map));
        }
        return true;
      case 'unlink':
        rows.removeWhere((r) => ids.contains(r['id']));
        return true;
    }
    throw _OdooError(200, 'odoo.exceptions.UserError', 'Unknown method $model.$method');
  }

  List<Map<String, Object?>> _rows(String model) => records[model] ?? const [];

  Never _missing(String model, int id) =>
      throw _OdooError(200, 'odoo.exceptions.MissingError', 'Record does not exist or has been deleted.\n(Record: $model($id,), User: $uid)');

  int _create(String model, Map<String, Object?> vals) {
    final f = fields[model] ?? const {};
    for (final e in f.entries) {
      if (e.value['required'] == true && e.key != 'id' && !vals.containsKey(e.key) && !(defaults[model]?.containsKey(e.key) ?? false)) {
        throw _OdooError(200, 'odoo.exceptions.ValidationError', "Missing required value for the field '${e.value['string']}' (${e.key})");
      }
    }
    final rows = records[model]!;
    final id = rows.fold<int>(0, (m, r) => (r['id'] as int) > m ? r['id'] as int : m) + 1;
    rows.add({'id': id, ...?defaults[model], ...vals});
    return id;
  }

  Iterable<Map<String, Object?>> _page(List<Map<String, Object?>> rows, Map<String, Object?> named) {
    var out = rows;
    if (named['offset'] is int) out = out.skip(named['offset'] as int).toList();
    if (named['limit'] is int) out = out.take(named['limit'] as int).toList();
    return out;
  }

  /// A domain of plain conditions (`=`, `!=`, `ilike`, `in`), joined by AND. Enough for the lookups of the tools.
  List<Map<String, Object?>> _filter(List<Map<String, Object?>> rows, Object? domain) {
    if (domain is! List) return List.of(rows);
    final leaves = [for (final item in domain) if (item is List) item];
    bool match(Map<String, Object?> row, List leaf) {
      final field = '${leaf[0]}';
      final op = '${leaf[1]}';
      final want = leaf[2];
      final have = row[field];
      switch (op) {
        case '=':
          return have == want;
        case '!=':
          return have != want;
        case 'ilike':
          return '$have'.toLowerCase().contains('$want'.toLowerCase());
        case 'in':
          return (want as List).contains(have) || (have is List && have.any((h) => want.contains(h)));
      }
      return true;
    }

    return [for (final r in rows) if (leaves.every((l) => match(r, l))) r];
  }

  Map<String, Object?> _read(String model, Map<String, Object?> row, Object? wanted) {
    final f = fields[model] ?? const {};
    final names = wanted is List ? [for (final n in wanted) '$n'] : [for (final k in row.keys) k];
    final out = <String, Object?>{'id': row['id']};
    for (final n in names) {
      // Odoo computes display_name for every model from its name.
      if (n == 'display_name' && !row.containsKey(n) && row['name'] != null) out[n] = row['name'];
      if (n == 'id' || !row.containsKey(n)) continue;
      final v = row[n];
      final type = f[n]?['type'];
      if (type == 'many2one' && v is int) {
        final target = records[f[n]!['relation']]?.where((r) => r['id'] == v).firstOrNull;
        out[n] = [v, target?['name'] ?? 'record $v'];
      } else {
        out[n] = v;
      }
    }
    return out;
  }
}
