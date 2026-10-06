import 'dart:convert';
import 'odoo_json2.dart';
import 'odoo_rpc_converter.dart';

/// Odoo 18 and older speak JSON-RPC: a session from `/web/session/authenticate`, then
/// `POST /web/dataset/call_kw/<model>/<method>` with a JSON-RPC envelope whose `params` carry the model, the method
/// and its arguments by position (`args`) and by name (`kwargs`). This writes an [OdooCall] (the JSON-2 shape every
/// tool of Studio works in) in that form.
abstract final class OdooJsonRpc {
  static const authenticatePath = '/web/session/authenticate';
  static const databaseListPath = '/web/database/list';

  static String callPath(String model, String method) => '/web/dataset/call_kw/$model/$method';

  static Map<String, Object?> envelope(Map<String, Object?> params, {int id = 1}) =>
      {'jsonrpc': '2.0', 'method': 'call', 'params': params, 'id': id};

  /// `args` and `kwargs` of [call]. The leading parameters the method is known by are passed by position, because
  /// that is what every version since 8.0 accepts (`name_search` called its domain `args` until 19, `search_count`
  /// called it `args` until 16); the rest, and every parameter of a method that is not known, by name. A
  /// recordset method gets the ids first. [ids] replaces `call.ids` (a placeholder for a `{{variable}}`).
  static ({List<Object?> args, Map<String, Object?> kwargs}) arguments(OdooCall call, {Object? ids}) =>
      argumentsOf(call.method, {...call.body, 'ids': ?ids});

  /// [arguments] for a JSON-2 body that is not a typed [OdooCall] (the checker works on what a person wrote): [named]
  /// holds `ids`, `context` and the method's parameters by name, whatever they are.
  static ({List<Object?> args, Map<String, Object?> kwargs}) argumentsOf(String method, Map<String, Object?> named) {
    final signature = OdooRpcConverter.signatureOf(method);
    final kwargs = <String, Object?>{...named};
    final ids = kwargs.remove('ids');
    final context = kwargs.remove('context');
    final args = <Object?>[];
    if (signature?.recordset ?? (ids is List && ids.isNotEmpty)) args.add(ids ?? const <Object?>[]);
    if (signature != null) {
      for (final name in signature.params) {
        if (!kwargs.containsKey(name)) break;
        args.add(kwargs.remove(name));
      }
    }
    // Before Odoo 19 a name search's domain is called `args`.
    if (method == 'name_search' && kwargs.containsKey('domain')) kwargs['args'] = kwargs.remove('domain');
    if (context is Map && context.isNotEmpty) kwargs['context'] = context;
    return (args: args, kwargs: kwargs);
  }

  /// The whole JSON-RPC request body of [call].
  static Map<String, Object?> callBody(OdooCall call, {Object? ids}) => callBodyOf(call.model, call.method, {...call.body, 'ids': ?ids});

  /// The JSON-RPC request body for a JSON-2 body [named] (see [argumentsOf]).
  static Map<String, Object?> callBodyOf(String model, String method, Map<String, Object?> named) {
    final a = argumentsOf(method, named);
    return envelope({'model': model, 'method': method, 'args': a.args, 'kwargs': a.kwargs});
  }

  /// The body as text for a saved request. With `idsVariable` the id is the bare `{{variable}}`, as in JSON-2.
  static String bodyText(OdooCall call) {
    const pretty = JsonEncoder.withIndent('  ');
    final variable = call.idsVariable;
    if (variable == null) return pretty.convert(callBody(call));
    const marker = '__postpilot_record_id__';
    return pretty.convert(callBody(call, ids: [marker])).replaceFirst(RegExp('\\[\\s*"$marker"\\s*\\]'), '[{{$variable}}]');
  }

  /// Everything but a cookie: the session is the login.
  static Map<String, String> headers() => {'Content-Type': 'application/json; charset=utf-8'};

  static OdooRequestDraft draft(OdooCall call, {String? name, String? note, String baseUrl = '{{${OdooVars.url}}}'}) =>
      OdooRequestDraft(
        name: name ?? '${call.model} · ${call.method}',
        url: '$baseUrl${callPath(call.model, call.method)}',
        headers: headers(),
        bodyText: bodyText(call),
        note: note,
      );

  /// The request that opens the session. Run it first (or let a collection's re-login run it): Odoo answers with the
  /// `session_id` cookie that every other request of the collection sends.
  static OdooRequestDraft loginDraft({String baseUrl = '{{${OdooVars.url}}}'}) => OdooRequestDraft(
        name: 'Log in to Odoo (run first)',
        url: '$baseUrl$authenticatePath',
        headers: headers(),
        bodyText: const JsonEncoder.withIndent('  ').convert(envelope({
          'db': '{{${OdooVars.database}}}',
          'login': '{{${OdooVars.login}}}',
          'password': '{{${OdooVars.password}}}',
        })),
        note: 'Opens the session the other requests of this collection use: Odoo answers with a `session_id` cookie and PostPilot '
            'sends it on every following request. Needs the variables {{${OdooVars.login}}} and {{${OdooVars.password}}} '
            '(a password, or an API key) and {{${OdooVars.database}}} in the environment. A wrong password answers 200 with an '
            'error in the body, so read the response. Run it again when Odoo says the session expired, or set this request as '
            'the collection\'s re-login request (Auth tab).',
      );

  /// The ready-made set for [model], written for the call_kw API: the same operations and notes as
  /// `OdooJson2.templatesFor`.
  static List<OdooRequestDraft> templatesFor(String model, {List<String> sampleFields = const ['display_name']}) => [
        for (final t in OdooJson2.templateCalls(model, sampleFields: sampleFields)) draft(t.call, name: t.name, note: t.note),
      ];
}

/// "Odoo Session Expired": a call that came back because the session cookie is gone or too old, not because the
/// call is wrong. Odoo answers these with HTTP 200 and a JSON-RPC error of code 100 (the status alone says nothing),
/// so the body is what tells.
abstract final class OdooSessionExpiry {
  /// True when [body] is the JSON-RPC error of an expired session.
  static bool isExpired(String body) {
    if (!body.contains('"error"') || body.length > 64 * 1024) return false;
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return false;
    }
    if (json is! Map || json['error'] is! Map) return false;
    final error = json['error'] as Map;
    if (error['code'] == 100) return true;
    final data = error['data'];
    return data is Map && '${data['name']}'.endsWith('SessionExpiredException');
  }

  static bool isExpiredBytes(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > 64 * 1024 || bytes.first != 0x7B) return false; // `{`
    return isExpired(utf8.decode(bytes, allowMalformed: true));
  }
}
