/// The source of the files every generated Odoo client shares. They are plain Dart (dio is the only package), written
/// once here and checked by compiling them (see `test/odoo/odoo_client_generator_test.dart`).
///
/// Nothing secret is ever part of this text: the API key, the password and the database are constructor arguments of
/// the generated client.
abstract final class OdooClientTemplates {
  static const exceptions = r'''/// Everything the Odoo client throws, mapped from the error Odoo sends. Match on the subclass:
///
///     try {
///       await partners.create(partner);
///     } on OdooValidationException catch (e) {
///       showError(e.message);
///     } on OdooException catch (e) {
///       log(e.toString());
///     }
sealed class OdooException implements Exception {
  const OdooException(this.message, {this.exceptionName, this.statusCode, this.debug});

  /// Odoo's own message. It never contains the API key or the password.
  final String message;

  /// The Python exception class Odoo raised (`odoo.exceptions.AccessError`), when it said.
  final String? exceptionName;

  /// The HTTP status of the answer, when there was one.
  final int? statusCode;

  /// The Python traceback. Odoo only sends it in debug mode.
  final String? debug;

  @override
  String toString() => '$runtimeType: $message';

  /// Reads [body] (a decoded JSON answer) as an Odoo error and returns null when it is none.
  ///
  /// Both shapes are understood: the JSON-RPC envelope `{"error": {"code", "message", "data": {...}}}` (always HTTP 200)
  /// and the JSON-2 body, which is the exception itself `{"name", "message", "arguments", "debug"}` with a 4xx / 5xx status.
  static OdooException? fromPayload(Object? body, {int? statusCode}) {
    if (body is! Map) return null;
    final error = body['error'];
    if (error is Map) {
      final data = error['data'];
      final info = data is Map ? data : const <Object?, Object?>{};
      final message = _text(info['message']) ?? _text(error['message']) ?? 'Odoo returned an error.';
      final code = error['code'];
      return _build(_text(info['name']) ?? '', message, statusCode, code is num ? code.toInt() : null, _text(info['debug']));
    }
    if ((statusCode ?? 0) >= 400 && body['name'] is String && body.containsKey('message')) {
      final arguments = body['arguments'];
      final message = _text(body['message']) ?? (arguments is List && arguments.isNotEmpty ? '${arguments.first}' : '');
      return _build(body['name'] as String, message, statusCode, null, _text(body['debug']));
    }
    return null;
  }

  static String? _text(Object? value) => value is String && value.isNotEmpty ? value : null;

  static OdooException _build(String name, String message, int? status, int? code, String? debug) {
    final short = name.split('.').last;
    // Odoo answers an expired session with HTTP 200 and the error code 100.
    if (code == 100 || short == 'SessionExpiredException') {
      return OdooSessionExpiredException(message, exceptionName: name, statusCode: status, debug: debug);
    }
    if (status == 401 || short == 'Unauthorized' || short == 'AccessDenied') {
      return OdooAuthException(message, exceptionName: name, statusCode: status, debug: debug);
    }
    return switch (short) {
      'AccessError' || 'Forbidden' => OdooAccessException(message, exceptionName: name, statusCode: status, debug: debug),
      'ValidationError' => OdooValidationException(message, exceptionName: name, statusCode: status, debug: debug),
      'MissingError' => OdooMissingRecordException(message, exceptionName: name, statusCode: status, debug: debug),
      'UserError' || 'Warning' || 'RedirectWarning' => OdooUserException(message, exceptionName: name, statusCode: status, debug: debug),
      _ when status == 403 => OdooAccessException(message, exceptionName: name, statusCode: status, debug: debug),
      _ => OdooServerException(message, exceptionName: name, statusCode: status, debug: debug),
    };
  }
}

/// The key or the login was not accepted (HTTP 401, `AccessDenied`).
final class OdooAuthException extends OdooException {
  const OdooAuthException(super.message, {super.exceptionName, super.statusCode, super.debug});
}

/// The user may not do this: no access right on the model, or a record rule forbids the record (`AccessError`).
final class OdooAccessException extends OdooException {
  const OdooAccessException(super.message, {super.exceptionName, super.statusCode, super.debug});
}

/// A constraint of the model rejected the values (`ValidationError`). The message says which.
final class OdooValidationException extends OdooException {
  const OdooValidationException(super.message, {super.exceptionName, super.statusCode, super.debug});
}

/// A record does not exist, or was deleted meanwhile (`MissingError`).
final class OdooMissingRecordException extends OdooException {
  const OdooMissingRecordException(super.message, {super.exceptionName, super.statusCode, super.debug});
}

/// Odoo refused on purpose and wrote a message for the person using the app (`UserError`, `Warning`, `RedirectWarning`).
final class OdooUserException extends OdooException {
  const OdooUserException(super.message, {super.exceptionName, super.statusCode, super.debug});
}

/// The session cookie of a JSON-RPC login is too old. [OdooRpcClient] logs in again by itself once; this is thrown
/// when that does not help either.
final class OdooSessionExpiredException extends OdooException {
  const OdooSessionExpiredException(super.message, {super.exceptionName, super.statusCode, super.debug});
}

/// Any other error of the server: an unknown model or method, an `IntegrityError`, a bug, an unexpected answer.
final class OdooServerException extends OdooException {
  const OdooServerException(super.message, {super.exceptionName, super.statusCode, super.debug});
}

/// No answer from Odoo: the host is unreachable, the connection timed out or the certificate was refused.
final class OdooNetworkException extends OdooException {
  const OdooNetworkException(super.message, {this.cause});

  /// The error of the HTTP client.
  final Object? cause;
}
''';

  static const domain = r'''/// A search domain, built with code instead of nested lists.
///
///     final domain = Domain.and([
///       Domain.eq('is_company', true),
///       Domain.or([Domain.ilike('name', 'azure'), Domain.ilike('email', 'azure')]),
///       Domain.inList('country_id', [233, 20]),
///     ]);
///     // or: Domain.eq('is_company', true) & (Domain.ilike('name', 'a') | Domain.ilike('email', 'a'))
///     await client.searchRead('res.partner', domain: domain);
///
/// [toJson] writes Odoo's prefix notation (`['&', ['a', '=', 1], ['b', '=', 2]]`) with every `&`, `|` and `!` explicit.
/// Dates and datetimes are written the way Odoo reads them (UTC, `2026-10-02 10:00:00`).
sealed class Domain {
  const Domain();

  /// Matches every record: the empty domain.
  static const Domain all = _All();

  /// Matches no record.
  static const Domain none = _None();

  /// One condition `(field, operator, value)`. The helpers below cover the usual operators.
  const factory Domain.leaf(String field, String op, Object? value) = _Leaf;

  static Domain eq(String field, Object? value) => Domain.leaf(field, '=', value);
  static Domain ne(String field, Object? value) => Domain.leaf(field, '!=', value);
  static Domain gt(String field, Object? value) => Domain.leaf(field, '>', value);
  static Domain ge(String field, Object? value) => Domain.leaf(field, '>=', value);
  static Domain lt(String field, Object? value) => Domain.leaf(field, '<', value);
  static Domain le(String field, Object? value) => Domain.leaf(field, '<=', value);

  /// `like` with the wildcards the caller writes (`%`, `_`).
  static Domain like(String field, String pattern) => Domain.leaf(field, 'like', pattern);

  /// Case-insensitive "contains".
  static Domain ilike(String field, String text) => Domain.leaf(field, 'ilike', text);
  static Domain inList(String field, Iterable<Object?> values) => Domain.leaf(field, 'in', values);
  static Domain notIn(String field, Iterable<Object?> values) => Domain.leaf(field, 'not in', values);

  /// The field has a value (Odoo stores an empty one as `False`).
  static Domain isSet(String field) => Domain.leaf(field, '!=', false);
  static Domain isNotSet(String field) => Domain.leaf(field, '=', false);
  static Domain childOf(String field, Object value) => Domain.leaf(field, 'child_of', value);
  static Domain parentOf(String field, Object value) => Domain.leaf(field, 'parent_of', value);

  /// `from <= field <= to`.
  static Domain between(String field, Object? from, Object? to) => and([ge(field, from), le(field, to)]);

  /// A condition on the records of a relation: `any('child_ids', Domain.eq('active', true))` (Odoo 17 and later).
  static Domain any(String field, Domain inner) => Domain.leaf(field, 'any', inner.toJson());
  static Domain notAny(String field, Domain inner) => Domain.leaf(field, 'not any', inner.toJson());

  /// Every term must match. An empty list matches everything.
  static Domain and(Iterable<Domain> terms) => _combine(true, terms);

  /// At least one term must match. An empty list matches nothing.
  static Domain or(Iterable<Domain> terms) => _combine(false, terms);

  Domain operator &(Domain other) => and([this, other]);
  Domain operator |(Domain other) => or([this, other]);

  /// Dart cannot overload `!`, so negation is `~domain` or `domain.not()`.
  Domain operator ~() => not();

  Domain not() => switch (this) {
        _All() => none,
        _None() => all,
        _Not(:final inner) => inner,
        _ => _Not(this),
      };

  /// The domain as Odoo takes it, ready to send as `domain`.
  List<Object?> toJson() => this is _All ? const <Object?>[] : _terms();

  @override
  String toString() => toJson().toString();

  List<Object?> _terms() => switch (this) {
        _All() => const <Object?>[<Object?>[1, '=', 1]],
        _None() => const <Object?>[<Object?>[0, '=', 1]],
        _Leaf(:final field, :final op, :final value) => <Object?>[<Object?>[field, op, _encode(value)]],
        _Not(:final inner) => <Object?>['!', ...inner._terms()],
        _Group(:final op, :final terms) => <Object?>[
            for (var i = 1; i < terms.length; i++) op,
            for (final term in terms) ...term._terms(),
          ],
      };

  static Domain _combine(bool isAnd, Iterable<Domain> input) {
    final terms = <Domain>[];
    for (final term in input) {
      switch (term) {
        case _All():
          // x AND true is x; x OR true is true.
          if (!isAnd) return all;
        case _None():
          if (isAnd) return none;
        case _Group(:final op, terms: final inner) when op == (isAnd ? '&' : '|'):
          terms.addAll(inner);
        default:
          terms.add(term);
      }
    }
    if (terms.isEmpty) return isAnd ? all : none;
    if (terms.length == 1) return terms.single;
    return _Group(isAnd ? '&' : '|', List.unmodifiable(terms));
  }

  static Object? _encode(Object? value) => switch (value) {
        DateTime date => _odooDateTime(date),
        Iterable<Object?> items => [for (final item in items) _encode(item)],
        _ => value,
      };
}

String _odooDateTime(DateTime value) {
  final utc = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
}

final class _Leaf extends Domain {
  const _Leaf(this.field, this.op, this.value);
  final String field;
  final String op;
  final Object? value;
}

final class _Not extends Domain {
  const _Not(this.inner);
  final Domain inner;
}

final class _Group extends Domain {
  const _Group(this.op, this.terms);

  /// `&` or `|`.
  final String op;
  final List<Domain> terms;
}

final class _All extends Domain {
  const _All();
}

final class _None extends Domain {
  const _None();
}
''';

  static const commands = r'''/// The tuples Odoo reads in a one2many or many2many field of `create` / `write` (the "x2many commands"):
///
///     await partners.create(partner, extra: {
///       'child_ids': [Command.create({'name': 'Brandon'}), Command.link(7)],
///       'category_id': [Command.set([1, 2])],
///     });
abstract final class Command {
  /// Creates a record from [values] and links it.
  static List<Object?> create(Map<String, Object?> values) => [0, 0, values];

  /// Writes [values] to the linked record [id].
  static List<Object?> update(int id, Map<String, Object?> values) => [1, id, values];

  /// Removes the record [id] from the relation and deletes it.
  static List<Object?> delete(int id) => [2, id, 0];

  /// Removes the record [id] from the relation, without deleting it.
  static List<Object?> unlink(int id) => [3, id, 0];

  /// Adds the existing record [id] to the relation.
  static List<Object?> link(int id) => [4, id, 0];

  /// Removes every record from the relation, without deleting them.
  static List<Object?> clear() => [5, 0, 0];

  /// Replaces the relation by exactly [ids].
  static List<Object?> set(List<int> ids) => [6, 0, ids];
}
''';

  static const page = r'''/// One page of a search: the records, where it starts and whether there is more.
final class OdooPage<T> {
  const OdooPage(this.items, {required this.offset, required this.limit, this.total});

  final List<T> items;
  final int offset;
  final int limit;

  /// The number of records matching the search, when it was asked for (`withCount: true`).
  final int? total;

  /// Whether another page follows. Without [total] a full page is taken to mean "probably".
  bool get hasMore {
    final all = total;
    return all != null ? offset + items.length < all : items.length >= limit;
  }

  /// The offset of the next page.
  int get nextOffset => offset + items.length;
}
''';

  static const clientHeader = r'''import 'package:dio/dio.dart';

import 'odoo_domain.dart';
import 'odoo_exception.dart';

/// A client for Odoo's External JSON-2 API (Odoo 19 and later): `POST /json/2/<model>/<method>` with
/// `Authorization: bearer <API key>` and the database in `X-Odoo-Database`.
///
/// The key, the database and the URL are constructor arguments. Nothing secret is written into generated code: read the
/// key from your secure storage or `--dart-define`, never commit it.
///
///     final client = OdooClient(
///       baseUrl: 'https://mycompany.odoo.com',
///       database: 'mycompany',
///       apiKey: const String.fromEnvironment('ODOO_API_KEY'),
///     );
///
/// Every method throws an [OdooException] (see odoo_exception.dart) and nothing else.
class OdooClient {
  OdooClient({
    required String baseUrl,
    required String apiKey,
    String? database,
    Dio? dio,
    Map<String, Object?> context = const {},
  })  : _baseUrl = _normalize(baseUrl),
        _apiKey = apiKey,
        _database = database,
        _dio = dio ?? Dio(),
        _context = context;

  final String _baseUrl;
  final String _apiKey;
  final String? _database;
  final Dio _dio;

  /// Sent as `context` with every call (`{'lang': 'de_DE', 'tz': 'Europe/Berlin'}`).
  final Map<String, Object?> _context;

  /// The server this client talks to (never the key).
  String get baseUrl => _baseUrl;

  static String _normalize(String url) {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    return trimmed.contains('://') ? trimmed : 'https://$trimmed';
  }

  /// Calls any method of a model: [ids] select the records of a recordset method (`read`, `write`, `unlink`), [params]
  /// are the method's arguments by name. Returns what the method returned.
  Future<Object?> call(
    String model,
    String method, {
    List<int> ids = const [],
    Map<String, Object?> params = const {},
    Map<String, Object?>? context,
  }) async {
    final merged = {..._context, ...?context};
    final database = _database;
    final response = await _post(
      '$_baseUrl/json/2/$model/$method',
      {
        if (ids.isNotEmpty) 'ids': ids,
        if (merged.isNotEmpty) 'context': merged,
        ...params,
      },
      {
        'Authorization': 'bearer $_apiKey',
        if (database != null && database.isNotEmpty) 'X-Odoo-Database': database,
      },
    );
    final status = response.statusCode ?? 0;
    final error = OdooException.fromPayload(response.data, statusCode: status);
    if (error != null) throw error;
    if (status == 401) {
      throw OdooAuthException('Odoo rejected the API key (HTTP 401). Check the key and the database name.', statusCode: status);
    }
    if (status == 403) {
      throw OdooAccessException('Odoo refused the call (HTTP 403): this user may not use the API.', statusCode: status);
    }
    if (status < 200 || status >= 300) {
      throw OdooServerException(
        'Odoo answered HTTP $status to $model.$method${status == 404 ? ': check the base URL, the model name and that its module is installed' : ''}.',
        statusCode: status,
      );
    }
    return response.data;
  }

  /// The records matching [domain] (a [Domain] or Odoo's own list), as maps. [fields] limits what is read.
  Future<List<Map<String, dynamic>>> searchRead(
    String model, {
    Object? domain,
    List<String>? fields,
    int? limit,
    int? offset,
    String? order,
    Map<String, Object?>? context,
  }) async {
    final result = await call(
      model,
      'search_read',
      params: {
        'domain': _domain(domain),
        if (fields != null) 'fields': fields,
        if (limit != null) 'limit': limit,
        if (offset != null && offset > 0) 'offset': offset,
        if (order != null) 'order': order,
      },
      context: context,
    );
    return _rows(result, '$model.search_read');
  }

  /// The records [ids] with [fields] (all fields without it).
  Future<List<Map<String, dynamic>>> read(
    String model,
    List<int> ids, {
    List<String>? fields,
    Map<String, Object?>? context,
  }) async {
    if (ids.isEmpty) return const [];
    final result = await call(model, 'read', ids: ids, params: {if (fields != null) 'fields': fields}, context: context);
    return _rows(result, '$model.read');
  }

  Future<int> searchCount(String model, {Object? domain, Map<String, Object?>? context}) async {
    final result = await call(model, 'search_count', params: {'domain': _domain(domain)}, context: context);
    if (result is num) return result.toInt();
    throw OdooServerException('Odoo answered $model.search_count with ${result.runtimeType}, expected a number.');
  }

  /// Creates one record per map of [valsList] and returns their ids.
  Future<List<int>> create(String model, List<Map<String, Object?>> valsList, {Map<String, Object?>? context}) async {
    final result = await call(model, 'create', params: {'vals_list': valsList}, context: context);
    if (result is List) return [for (final id in result) (id as num).toInt()];
    if (result is num) return [result.toInt()];
    throw OdooServerException('Odoo answered $model.create with ${result.runtimeType}, expected the ids of the new records.');
  }

  /// Writes [values] to every record of [ids].
  Future<bool> write(String model, List<int> ids, Map<String, Object?> values, {Map<String, Object?>? context}) async {
    if (ids.isEmpty) return true;
    return await call(model, 'write', ids: ids, params: {'vals': values}, context: context) == true;
  }

  /// Deletes the records [ids]. This cannot be undone.
  Future<bool> unlink(String model, List<int> ids, {Map<String, Object?>? context}) async {
    if (ids.isEmpty) return true;
    return await call(model, 'unlink', ids: ids, context: context) == true;
  }

  /// The fields of [model]: name to definition (`type`, `string`, `required`, `relation`, ...).
  Future<Map<String, dynamic>> fieldsGet(
    String model, {
    List<String> attributes = const ['string', 'type', 'required', 'readonly', 'store', 'relation', 'selection', 'help'],
  }) async {
    final result = await call(model, 'fields_get', params: {'attributes': attributes});
    if (result is Map) return Map<String, dynamic>.from(result);
    throw OdooServerException('Odoo answered $model.fields_get with ${result.runtimeType}, expected a map of fields.');
  }

  /// `(id, display name)` of the records whose name matches [name], the way a many2one box searches.
  Future<List<(int, String)>> nameSearch(
    String model, {
    String name = '',
    Object? domain,
    String operator = 'ilike',
    int limit = 8,
    Map<String, Object?>? context,
  }) async {
    final result = await call(
      model,
      'name_search',
      params: {'name': name, 'domain': _domain(domain), 'operator': operator, 'limit': limit},
      context: context,
    );
    if (result is! List) {
      throw OdooServerException('Odoo answered $model.name_search with ${result.runtimeType}, expected a list.');
    }
    return [
      for (final pair in result)
        if (pair is List && pair.length >= 2 && pair.first is num) ((pair.first as num).toInt(), '${pair[1]}'),
    ];
  }

  static Object _domain(Object? domain) => domain is Domain ? domain.toJson() : (domain ?? const <Object?>[]);

  static List<Map<String, dynamic>> _rows(Object? result, String what) {
    if (result is! List) throw OdooServerException('Odoo answered $what with ${result.runtimeType}, expected a list of records.');
    return [for (final row in result) Map<String, dynamic>.from(row as Map)];
  }

  Future<Response<Object?>> _post(String url, Object? body, Map<String, String> headers) async {
    try {
      return await _dio.post<Object?>(
        url,
        data: body,
        options: Options(
          headers: headers,
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
          // Odoo reports its errors in the body of a 4xx / 5xx answer: they are read, not thrown by dio.
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw OdooNetworkException('Could not reach Odoo at $_baseUrl: ${e.message ?? e.type.name}', cause: e);
    }
  }
}
''';

  static const rpcClient = r'''
/// A client for Odoo 18 and older, which speak JSON-RPC: a session from `/web/session/authenticate`, then
/// `/web/dataset/call_kw/<model>/<method>`. It has every method of [OdooClient], so the repositories take either.
///
/// A session that Odoo says has expired is opened again once and the call is repeated. On Flutter web the browser keeps
/// the cookie itself, and Odoo must allow cross-origin requests with credentials.
///
///     final client = OdooRpcClient(
///       baseUrl: 'https://mycompany.example.com',
///       database: 'mycompany',
///       login: 'admin',
///       password: const String.fromEnvironment('ODOO_PASSWORD'), // a password or an API key
///     );
class OdooRpcClient extends OdooClient {
  OdooRpcClient({
    required String baseUrl,
    required String database,
    required String login,
    required String password,
    Dio? dio,
    Map<String, Object?> context = const {},
  })  : _db = database,
        _login = login,
        _password = password,
        super(baseUrl: baseUrl, apiKey: password, database: database, dio: dio, context: context);

  final String _db;
  final String _login;
  final String _password;
  String? _cookie;
  Future<void>? _session;
  int _requestId = 0;

  /// The leading arguments `call_kw` takes by position for each method (every Odoo version since 8.0 accepts them so).
  static const _positional = <String, List<String>>{
    'search_read': ['domain'],
    'search_count': ['domain'],
    'create': ['vals_list'],
    'write': ['vals'],
    'name_search': ['name', 'domain', 'operator', 'limit'],
  };

  /// Methods that act on records: the ids come first.
  static const _recordsetMethods = {'read', 'write', 'unlink'};

  @override
  Future<Object?> call(
    String model,
    String method, {
    List<int> ids = const [],
    Map<String, Object?> params = const {},
    Map<String, Object?>? context,
  }) async {
    await _ensureSession();
    try {
      return await _callKw(model, method, ids, params, context);
    } on OdooSessionExpiredException {
      // The cookie is too old: log in again and repeat the call once.
      _session = null;
      await _ensureSession();
      return _callKw(model, method, ids, params, context);
    }
  }

  /// Opens the session now instead of at the first call, to find out early that the login is wrong.
  Future<void> login() => _ensureSession();

  Future<void> _ensureSession() {
    return _session ??= () async {
      try {
        await _authenticate();
      } catch (_) {
        _session = null;
        rethrow;
      }
    }();
  }

  Future<void> _authenticate() async {
    final response = await _post(
      '$_baseUrl/web/session/authenticate',
      _envelope({'db': _db, 'login': _login, 'password': _password}),
      const {},
    );
    final error = OdooException.fromPayload(response.data, statusCode: response.statusCode);
    if (error != null) throw error;
    final data = response.data;
    final result = data is Map ? data['result'] : null;
    final uid = result is Map ? result['uid'] : null;
    if (uid is! int) {
      throw OdooAuthException(
        'Odoo did not log "$_login" in to database "$_db". Check the login, the password (or API key) and the database name.',
        statusCode: response.statusCode,
      );
    }
    String? cookie;
    for (final line in response.headers['set-cookie'] ?? const <String>[]) {
      final match = RegExp(r'(?:^|[\s,;])session_id=([^;\s,]+)').firstMatch(line);
      if (match != null) cookie = 'session_id=${match[1]}';
    }
    if (cookie == null && result is Map && result['session_id'] is String) cookie = 'session_id=${result['session_id']}';
    // Without a cookie (the browser keeps it itself on web) the calls rely on the HTTP client's own cookie handling.
    _cookie = cookie;
  }

  Future<Object?> _callKw(
    String model,
    String method,
    List<int> ids,
    Map<String, Object?> params,
    Map<String, Object?>? context,
  ) async {
    final named = <String, Object?>{...params};
    final args = <Object?>[];
    if (_recordsetMethods.contains(method)) args.add(ids);
    for (final name in _positional[method] ?? const <String>[]) {
      if (!named.containsKey(name)) break;
      args.add(named.remove(name));
    }
    final merged = {..._context, ...?context};
    if (merged.isNotEmpty) named['context'] = merged;
    final cookie = _cookie;
    final response = await _post(
      '$_baseUrl/web/dataset/call_kw/$model/$method',
      _envelope({'model': model, 'method': method, 'args': args, 'kwargs': named}),
      {if (cookie != null) 'Cookie': cookie},
    );
    final error = OdooException.fromPayload(response.data, statusCode: response.statusCode);
    if (error != null) throw error;
    final data = response.data;
    if (data is Map && data.containsKey('result')) return data['result'];
    throw OdooServerException(
      'Odoo answered HTTP ${response.statusCode} to $model.$method with something that is not a JSON-RPC result.',
      statusCode: response.statusCode,
    );
  }

  Map<String, Object?> _envelope(Map<String, Object?> params) =>
      {'jsonrpc': '2.0', 'method': 'call', 'params': params, 'id': ++_requestId};
}
''';
}
