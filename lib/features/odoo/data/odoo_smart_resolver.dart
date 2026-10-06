// Pure Dart (no Flutter): the command line looks smart references up with this too.
import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_http_response.dart';
import '../../documentation/domain/services/secret_masker.dart';
import '../domain/entities/odoo_connection.dart';
import '../domain/entities/odoo_result.dart';
import '../domain/services/odoo_json2.dart';
import '../domain/services/odoo_jsonrpc.dart';
import '../domain/services/smart_references.dart';
import 'odoo_transport.dart';

/// Looks `{{xmlid:base.main_company}}` and `{{ref:res.partner:Azure Interior}}` up on the live Odoo server when a
/// request is sent, so the same request works against every database: ids differ between them, XML-IDs and names
/// do not.
///
/// The server is the one the request itself goes to, and the credentials are the request's own (its bearer token and
/// database for JSON-2; the `odooLogin` / `odooPassword` variables, or a session some other request opened, for
/// JSON-RPC). An answer is kept for [ttl], per server and database. Lookups only read.
final class OdooSmartReferenceResolver implements SmartReferenceResolver {
  final Json2Transport _json2;
  final JsonRpcTransport _jsonRpc;
  final DateTime Function() _now;
  final Duration ttl;
  final Map<String, ({int id, DateTime expires})> _cache = {};

  OdooSmartReferenceResolver(
    ApiClient api, {
    ApiRequestOptions Function()? options,
    DateTime Function()? now,
    this.ttl = const Duration(minutes: 10),
  })  : _json2 = Json2Transport(api, options: options),
        _jsonRpc = JsonRpcTransport(api, options: options),
        _now = now ?? DateTime.now;

  /// Forgets every answer, so the next send looks everything up again (a record was deleted and created again).
  void clearCache() => _cache.clear();

  int get cachedCount => _cache.length;

  @override
  Future<Map<String, String>> resolve(SmartReferenceContext context, Iterable<String> keys) async {
    final references = <SmartReference>[];
    for (final key in keys.toSet()) {
      final reference = SmartReference.tryParse(key);
      if (reference == null) throw SmartReferenceException(SmartReferences.problemWith(key)!);
      references.add(reference);
    }
    if (references.isEmpty) return const {};
    final connection = connectionFor(context);
    final cookie = _header(context.headers, 'cookie');
    final resolved = <String, String>{};
    for (final reference in references) {
      final cacheKey = '${connection.identity}|${reference.key}';
      final hit = _cache[cacheKey];
      if (hit != null && hit.expires.isAfter(_now())) {
        resolved[reference.key] = '${hit.id}';
        continue;
      }
      final int id;
      try {
        id = reference.kind == SmartReferenceKind.xmlId
            ? await _byXmlId(connection, reference, cookie)
            : await _byName(connection, reference, cookie);
      } on NetworkException catch (e) {
        throw SmartReferenceException(
          'Could not reach ${_origin(connection)} to look up ${reference.token}: ${SecretMasker.maskMessage(e.summary ?? e.message)}',
        );
      }
      _cache[cacheKey] = (id: id, expires: _now().add(ttl));
      resolved[reference.key] = '$id';
    }
    return resolved;
  }

  /// The server and credentials of the request that carries the tokens. Its URL says which API it speaks
  /// (`/json/2/...` or `/web/dataset/call_kw/...`); without an Odoo path the environment's `odooUrl` is used.
  static OdooConnection connectionFor(SmartReferenceContext context) {
    final url = context.url.trim();
    final marker = RegExp(r'/(json/2|web/dataset|web/session|web/database|jsonrpc)(?=[/?#]|$)').firstMatch(url);
    String? base;
    OdooProtocol protocol;
    if (marker != null) {
      base = url.substring(0, marker.start);
      protocol = marker[1] == 'json/2' ? OdooProtocol.json2 : OdooProtocol.jsonRpc;
    } else {
      final configured = context.variable(OdooVars.url)?.trim() ?? '';
      if (configured.isEmpty) {
        throw SmartReferenceException(
          '{{xmlid:...}} and {{ref:...}} are looked up on an Odoo server, but this request is not an Odoo call: '
          'its URL has no /json/2/<model>/<method> or /web/dataset/call_kw part, and there is no ${OdooVars.url} variable to fall back on.',
        );
      }
      base = configured;
      protocol = OdooProtocol.fromId(context.variable(OdooVars.protocol));
    }
    final database = _header(context.headers, 'x-odoo-database') ?? context.variable(OdooVars.database) ?? '';
    if (protocol == OdooProtocol.json2) {
      final authorization = _header(context.headers, 'authorization') ?? '';
      final bearer = RegExp(r'^bearer\s+(.+)$', caseSensitive: false).firstMatch(authorization.trim())?[1] ?? context.variable(OdooVars.apiKey) ?? '';
      if (bearer.trim().isEmpty) {
        throw const SmartReferenceException(
          'The request sends no API key (an "Authorization: bearer ..." header), so {{xmlid:...}} and {{ref:...}} cannot be looked up for it.',
        );
      }
      return OdooConnection(baseUrl: base, database: database, apiKey: bearer.trim());
    }
    return OdooConnection(
      baseUrl: base,
      database: database,
      apiKey: context.variable(OdooVars.password) ?? context.variable(OdooVars.apiKey) ?? '',
      protocol: OdooProtocol.jsonRpc,
      login: context.variable(OdooVars.login) ?? '',
    );
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  String _origin(OdooConnection connection) => SecretMasker.maskUrl(connection.normalizedUrl);

  Future<OdooResult> _call(OdooConnection connection, OdooCall call, String? cookie) async {
    if (connection.protocol == OdooProtocol.json2) return _json2.call(connection, call);
    // Without a login to use the session of another request (the Log in request of the collection) is all there is.
    final hasLogin = connection.login.trim().isNotEmpty && connection.apiKey.isNotEmpty;
    if (hasLogin) return _jsonRpc.call(connection, call);
    final r = await _jsonRpc.callWithCookie(connection, call, cookie);
    if (OdooSessionExpiry.isExpired(r.body)) {
      throw SmartReferenceException(
        'The Odoo session of ${_origin(connection)} is not open or has expired. Run the "Log in" request of your collection first, '
        'or define ${OdooVars.login} and ${OdooVars.password} in the environment so PostPilot logs in by itself.',
      );
    }
    return r;
  }

  static bool _denied(OdooResult r) =>
      r.status == 403 || (r.error?.exception.endsWith('AccessError') ?? false) || (r.error?.exception.endsWith('Forbidden') ?? false);

  SmartReferenceException _failed(OdooConnection connection, SmartReference reference, OdooResult r) => SmartReferenceException(
        'Could not look up ${reference.token} on ${_origin(connection)}: '
        '${r.failureText(jsonRpc: connection.protocol == OdooProtocol.jsonRpc)}',
      );

  Future<int> _byXmlId(OdooConnection connection, SmartReference reference, String? cookie) async {
    final read = await _call(
      connection,
      OdooCall(model: 'ir.model.data', method: 'search_read', params: {
        'domain': [['module', '=', reference.module], ['name', '=', reference.xmlName]],
        'fields': ['model', 'res_id'],
        'limit': 1,
      }),
      cookie,
    );
    final rows = read.json;
    if (read.ok && rows is List) {
      if (rows.isNotEmpty && rows.first is Map && (rows.first as Map)['res_id'] is int) return (rows.first as Map)['res_id'] as int;
      throw SmartReferenceException(_xmlIdNotFound(connection, reference));
    }
    if (!_denied(read)) throw _failed(connection, reference, read);

    // Only administrators may read ir.model.data; every user may ask Odoo to resolve an XML-ID it can read.
    final check = await _call(
      connection,
      OdooCall(model: 'ir.model.data', method: 'check_object_reference', params: {'module': reference.module, 'xml_id': reference.xmlName}),
      cookie,
    );
    final pair = check.json;
    if (check.ok && pair is List && pair.length >= 2 && pair[1] is int) return pair[1] as int;
    final text = '${check.error?.message ?? ''} ${check.error?.exception ?? ''}';
    if (text.contains('External ID not found') || text.contains('ValueError')) {
      throw SmartReferenceException(_xmlIdNotFound(connection, reference));
    }
    if (_denied(check)) {
      throw SmartReferenceException(
        '${reference.describe} exists on ${_origin(connection)} but this user may not read it, or ir.model.data: '
        'use a user with access, or the numeric id.',
      );
    }
    throw _failed(connection, reference, check);
  }

  String _xmlIdNotFound(OdooConnection connection, SmartReference reference) {
    final db = connection.database.trim();
    return '${reference.describe} not found on ${_origin(connection)}${db.isEmpty ? '' : ' (database $db)'}. '
        'Check the spelling (module.name) and that the module that defines it is installed.';
  }

  Future<int> _byName(OdooConnection connection, SmartReference reference, String? cookie) async {
    Future<({OdooResult result, List<(int, String)> rows})> search(String operator) async {
      final r = await _call(
        connection,
        OdooCall(model: reference.model, method: 'name_search', params: {'name': reference.recordName, 'operator': operator, 'limit': 5}),
        cookie,
      );
      final json = r.json;
      return (
        result: r,
        rows: [
          if (r.ok && json is List)
            for (final pair in json)
              if (pair is List && pair.length >= 2 && pair.first is int) (pair.first as int, '${pair[1]}'),
        ],
      );
    }

    final exact = await search('=');
    if (!exact.result.ok) throw _failed(connection, reference, exact.result);
    final rows = exact.rows;
    if (rows.length == 1) return rows.single.$1;
    final where = _origin(connection);
    if (rows.length > 1) {
      throw SmartReferenceException(
        '${reference.describe} matches ${rows.length} records on $where (${rows.map((r) => '${r.$1}: ${r.$2}').join('; ')}). '
        'Use {{xmlid:module.name}} or a name that is unique.',
      );
    }
    final similar = await search('ilike');
    final hint = similar.rows.isEmpty
        ? ''
        : ' Similar: ${similar.rows.map((r) => '${r.$1}: ${r.$2}').join('; ')}.';
    throw SmartReferenceException('No record of ${reference.model} is named "${reference.recordName}" on $where.$hint');
  }
}
