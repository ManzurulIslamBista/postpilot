// Pure Dart (no Flutter): the command line resolves `{{xmlid:...}}` tokens through these too.
import 'dart:convert';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_http_response.dart';
import '../domain/entities/odoo_connection.dart';
import '../domain/entities/odoo_result.dart';
import '../domain/services/odoo_error_parser.dart';
import '../domain/services/odoo_json2.dart';
import '../domain/services/odoo_jsonrpc.dart';

/// One way of calling an Odoo server. Everything of Studio (the connection test, the model explorer, the domain and
/// payload builders, the request checker, the error doctor) talks to the server through this, so it works the same
/// with Odoo 19's JSON-2 API and with the JSON-RPC session of Odoo 18 and older.
abstract interface class OdooTransport {
  OdooProtocol get protocol;

  /// Runs [call] on the server. Its [OdooResult.json] is the method's return value for either API.
  Future<OdooResult> call(OdooConnection connection, OdooCall call);

  /// Checks that the server accepts the credentials: with JSON-2 a harmless `context_get`, with JSON-RPC the login
  /// itself. The result's `json` is what the server told about the user (`lang`, `tz`; with a session also `uid`,
  /// `username`, `server_version`).
  Future<OdooResult> connect(OdooConnection connection);
}

/// The text and the decoded JSON of a response.
class _Answer {
  final ApiHttpResponse response;
  final String text;
  final Object? json;
  _Answer(this.response, this.text, this.json);

  static Future<_Answer> post(
    ApiClient api,
    ApiRequestOptions options,
    String url,
    Map<String, String> headers,
    Object? body,
  ) async {
    final response = await api.send(
      ApiRequestSpec(method: 'POST', url: url, headers: headers, body: utf8.encode(jsonEncode(body)), options: options),
    );
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      // An HTML error page from a proxy, for instance.
    }
    return _Answer(response, text, json);
  }
}

/// Odoo 19 and later: `POST /json/2/<model>/<method>` with the API key as bearer token.
final class Json2Transport implements OdooTransport {
  final ApiClient _api;
  final ApiRequestOptions Function() _options;

  /// [options] is asked for on every call, so a changed proxy or timeout setting applies at once.
  Json2Transport(this._api, {ApiRequestOptions Function()? options}) : _options = options ?? (() => const ApiRequestOptions());

  @override
  OdooProtocol get protocol => OdooProtocol.json2;

  @override
  Future<OdooResult> call(OdooConnection connection, OdooCall call) async {
    final answer = await _Answer.post(
      _api,
      _options(),
      '${connection.normalizedUrl}${call.path}',
      OdooJson2.headers(apiKey: connection.apiKey.trim(), database: connection.database.trim()),
      call.body,
    );
    return OdooResult(
      status: answer.response.statusCode,
      body: answer.text,
      json: answer.json,
      error: OdooErrorParser.parse(answer.text, statusCode: answer.response.statusCode),
      duration: answer.response.duration,
    );
  }

  @override
  Future<OdooResult> connect(OdooConnection connection) =>
      call(connection, const OdooCall(model: 'res.users', method: 'context_get'));
}

/// What an opened session holds. [cookie] is sent as the `Cookie` header of every call; it is never shown or logged.
final class OdooSession {
  final String cookie;
  final int uid;

  /// The login's answer: `username`, `server_version`, `user_context`, `db`...
  final Map<String, Object?> info;
  const OdooSession({required this.cookie, required this.uid, required this.info});
}

/// Odoo 18 and older: a session from `POST /web/session/authenticate`, kept as its cookie, then
/// `POST /web/dataset/call_kw/<model>/<method>`. A session that Odoo says has expired is opened again, once, and the
/// call is repeated; a second expiry is reported as it is.
final class JsonRpcTransport implements OdooTransport {
  final ApiClient _api;
  final ApiRequestOptions Function() _options;
  final Map<String, OdooSession> _sessions = {};

  JsonRpcTransport(this._api, {ApiRequestOptions Function()? options}) : _options = options ?? (() => const ApiRequestOptions());

  @override
  OdooProtocol get protocol => OdooProtocol.jsonRpc;

  /// The open session of [connection], without opening one.
  OdooSession? sessionOf(OdooConnection connection) => _sessions[connection.identity];

  /// Drops the session, so the next call logs in again (a changed password, a different user).
  void forget(OdooConnection connection) => _sessions.remove(connection.identity);

  void forgetAll() => _sessions.clear();

  @override
  Future<OdooResult> call(OdooConnection connection, OdooCall call) async {
    var session = _sessions[connection.identity];
    if (session == null) {
      final login = await _login(connection);
      if (login.failure != null) return login.failure!;
      session = login.session;
    }
    var answer = await _callKw(connection, call, session!);
    if (OdooSessionExpiry.isExpired(answer.text)) {
      _sessions.remove(connection.identity);
      final login = await _login(connection);
      if (login.failure != null) return login.failure!;
      answer = await _callKw(connection, call, login.session!);
    }
    return _result(answer);
  }

  @override
  Future<OdooResult> connect(OdooConnection connection) async {
    _sessions.remove(connection.identity);
    final login = await _login(connection);
    if (login.failure != null) return login.failure!;
    final info = login.session!.info;
    return OdooResult(status: 200, body: jsonEncode(info), json: info, error: null, duration: login.duration);
  }

  /// The databases of the server. Many servers have this switched off (`list_db = False`); [OdooDatabases.problem]
  /// then says so, and the database name is typed.
  Future<OdooDatabases> databases(OdooConnection connection) async {
    const off = 'This server does not list its databases (it is usually switched off with list_db = False): type the name.';
    try {
      final answer = await _Answer.post(
        _api,
        _options(),
        '${connection.normalizedUrl}${OdooJsonRpc.databaseListPath}',
        OdooJsonRpc.headers(),
        OdooJsonRpc.envelope(const {}),
      );
      final json = answer.json;
      if (json is Map && json['result'] is List) {
        return OdooDatabases([for (final name in json['result'] as List) if (name is String) name]);
      }
      return const OdooDatabases([], problem: off);
    } on Object {
      return const OdooDatabases([], problem: 'Could not ask the server for its databases: type the name.');
    }
  }

  /// A call that logs in by no means of its own: it sends [cookie] (the `Cookie` header of the request it serves) and
  /// whatever cookies the sender keeps, so it works inside a session some other request opened. An expired session
  /// is reported, not renewed: there are no credentials to renew it with.
  Future<OdooResult> callWithCookie(OdooConnection connection, OdooCall call, String? cookie) async {
    final answer = await _Answer.post(
      _api,
      _options(),
      '${connection.normalizedUrl}${OdooJsonRpc.callPath(call.model, call.method)}',
      {...OdooJsonRpc.headers(), if (cookie != null && cookie.trim().isNotEmpty) 'Cookie': cookie},
      OdooJsonRpc.callBody(call),
    );
    return _result(answer);
  }

  Future<_Answer> _callKw(OdooConnection connection, OdooCall call, OdooSession session) => _Answer.post(
        _api,
        _options(),
        '${connection.normalizedUrl}${OdooJsonRpc.callPath(call.model, call.method)}',
        {...OdooJsonRpc.headers(), 'Cookie': session.cookie},
        OdooJsonRpc.callBody(call),
      );

  /// The envelope taken off: what a call returned, in the shape JSON-2 would have answered.
  OdooResult _result(_Answer answer) {
    final error = OdooErrorParser.parse(answer.text, statusCode: answer.response.statusCode);
    final json = answer.json;
    if (error == null && json is Map && json['jsonrpc'] != null && json.containsKey('result')) {
      final result = json['result'];
      return OdooResult(
        status: answer.response.statusCode,
        body: jsonEncode(result),
        json: result,
        error: null,
        duration: answer.response.duration,
      );
    }
    return OdooResult(
      status: answer.response.statusCode,
      body: answer.text,
      json: json,
      error: error,
      duration: answer.response.duration,
    );
  }

  Future<({OdooSession? session, OdooResult? failure, Duration duration})> _login(OdooConnection connection) async {
    var database = connection.database.trim();
    if (database.isEmpty) {
      final listed = await databases(connection);
      if (listed.names.length != 1) {
        return (
          session: null,
          failure: OdooResult.failure(
            title: 'Database needed',
            message: listed.names.isEmpty
                ? 'Enter the name of the database to log in to. ${listed.problem ?? ''}'.trim()
                : 'This server has several databases (${listed.names.join(', ')}): choose one.',
          ),
          duration: Duration.zero,
        );
      }
      database = listed.names.single;
    }

    final answer = await _Answer.post(
      _api,
      _options(),
      '${connection.normalizedUrl}${OdooJsonRpc.authenticatePath}',
      OdooJsonRpc.headers(),
      OdooJsonRpc.envelope({'db': database, 'login': connection.login.trim(), 'password': connection.apiKey}),
    );
    final duration = answer.response.duration;
    final error = OdooErrorParser.parse(answer.text, statusCode: answer.response.statusCode);
    if (error != null) {
      final denied = error.exception.endsWith('AccessDenied') || error.message.toLowerCase().contains('access denied');
      return (
        session: null,
        failure: denied
            ? OdooResult.failure(
                title: 'Wrong login or password',
                message: error.message,
                hint: 'Check the login and the password (or API key) for database "$database". '
                    'Two-factor authentication blocks a plain password: use an API key as the password.',
                status: answer.response.statusCode,
                exception: error.exception,
                duration: duration,
              )
            : OdooResult(status: answer.response.statusCode, body: answer.text, json: answer.json, error: error, duration: duration),
        duration: duration,
      );
    }
    final json = answer.json;
    final result = json is Map && json['result'] is Map ? Map<String, Object?>.from(json['result'] as Map) : null;
    if (result == null) {
      return (
        session: null,
        failure: OdooResult.failure(
          title: 'Not an Odoo JSON-RPC server',
          message: 'The server answered ${answer.response.statusCode} to /web/session/authenticate with something that is not a JSON-RPC result.',
          hint: 'Check the URL. Odoo 19 and later use the JSON-2 API: choose that option instead.',
          status: answer.response.statusCode,
          duration: duration,
        ),
        duration: duration,
      );
    }
    final uid = result['uid'];
    if (uid is! int) {
      return (
        session: null,
        failure: OdooResult.failure(
          title: 'Wrong login or password',
          message: 'The server did not log "${connection.login.trim()}" in to database "$database".',
          hint: 'Check the login and the password (or API key).',
          status: answer.response.statusCode,
          duration: duration,
        ),
        duration: duration,
      );
    }
    final cookie = _sessionCookie(answer.response) ?? (result['session_id'] is String ? 'session_id=${result['session_id']}' : null);
    if (cookie == null) {
      return (
        session: null,
        failure: OdooResult.failure(
          title: 'No session cookie',
          message: 'The server logged in but sent no session_id cookie, so later calls cannot be tied to the login.',
          hint: 'A reverse proxy may be removing Set-Cookie headers.',
          status: answer.response.statusCode,
          duration: duration,
        ),
        duration: duration,
      );
    }
    final session = OdooSession(cookie: cookie, uid: uid, info: result);
    _sessions[connection.identity] = session;
    return (session: session, failure: null, duration: duration);
  }

  /// `session_id=<token>` from the response's cookies; the other cookies and their attributes are of no use here.
  static String? _sessionCookie(ApiHttpResponse response) {
    final lines = [...response.setCookies, ...response.headers.entries.where((e) => e.key.toLowerCase() == 'set-cookie').map((e) => e.value)];
    for (final line in lines) {
      final match = RegExp(r'(?:^|[\s,;])session_id=([^;\s,]+)').firstMatch(line);
      if (match != null) return 'session_id=${match[1]}';
    }
    return null;
  }
}
