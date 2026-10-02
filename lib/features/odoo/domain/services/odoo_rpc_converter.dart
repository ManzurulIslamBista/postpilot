import 'dart:convert';
import 'odoo_json2.dart';
import 'python_literal.dart';

/// The outcome of converting an old-style Odoo call.
final class OdooConversion {
  final OdooCall call;

  /// Things the person should check: a positional argument that could not be
  /// named, a method that no longer exists in recent versions.
  final List<String> notes;
  final String source;

  const OdooConversion(this.call, this.notes, this.source);
}

final class OdooConversionResult {
  final OdooConversion? conversion;
  final String? error;
  const OdooConversionResult.ok(OdooConversion this.conversion) : error = null;
  const OdooConversionResult.failed(String this.error) : conversion = null;
}

class _Signature {
  /// Parameter names in positional order, after the ids of a recordset method.
  final List<String> params;
  final bool recordset;
  final String? note;
  const _Signature(this.params, {this.recordset = false, this.note});
}

/// Rewrites calls made through the deprecated XML-RPC / JSON-RPC endpoints
/// (`execute_kw`, `/web/dataset/call_kw`, `/web/dataset/search_read`) as JSON-2
/// requests. Those endpoints pass arguments by position; JSON-2 passes them by
/// name, so the conversion needs each method's parameter names.
abstract final class OdooRpcConverter {
  static const _signatures = <String, _Signature>{
    'search': _Signature(['domain', 'offset', 'limit', 'order']),
    'search_count': _Signature(['domain', 'limit']),
    'search_read': _Signature(['domain', 'fields', 'offset', 'limit', 'order']),
    'read': _Signature(['fields', 'load'], recordset: true),
    'create': _Signature(['vals_list']),
    'write': _Signature(['vals'], recordset: true),
    'unlink': _Signature([], recordset: true),
    'fields_get': _Signature(['allfields', 'attributes']),
    'name_search': _Signature(['name', 'domain', 'operator', 'limit']),
    'default_get': _Signature(['fields_list']),
    'copy': _Signature(['default'], recordset: true),
    'exists': _Signature([], recordset: true),
    'read_group': _Signature(
      ['domain', 'fields', 'groupby', 'offset', 'limit', 'orderby', 'lazy'],
      note: 'read_group is deprecated in recent Odoo versions: prefer formatted_read_group.',
    ),
    'web_search_read': _Signature(['domain', 'specification', 'offset', 'limit', 'order', 'count_limit']),
    'web_read': _Signature(['specification'], recordset: true),
    'name_get': _Signature([], recordset: true, note: 'name_get was removed: read display_name instead.'),
    'check_access_rights': _Signature(['operation', 'raise_exception'],
        note: 'check_access_rights was removed: use has_access(operation) on the records.'),
  };

  static OdooConversionResult convert(String input) {
    final text = input.trim();
    if (text.isEmpty) return const OdooConversionResult.failed('Paste an old XML-RPC / JSON-RPC call to convert.');
    if (text.startsWith('{')) return _fromJson(text);
    return _fromPython(text);
  }

  // --- JSON bodies -------------------------------------------------------------

  static OdooConversionResult _fromJson(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      return OdooConversionResult.failed('That is not valid JSON: ${e.message}');
    }
    if (json is! Map) return const OdooConversionResult.failed('Expected a JSON object.');
    final params = json['params'] is Map ? json['params'] as Map : json;

    // /jsonrpc: service "object", method execute / execute_kw.
    if (params['service'] == 'object' && params['args'] is List) {
      final method = params['method'];
      final a = params['args'] as List;
      if (a.length < 5) return const OdooConversionResult.failed('The call has too few arguments for execute_kw.');
      final model = '${a[3]}';
      final rpcMethod = '${a[4]}';
      if (method == 'execute_kw') {
        return _build(model, rpcMethod, a.length > 5 && a[5] is List ? a[5] as List : const [],
            a.length > 6 && a[6] is Map ? Map<String, Object?>.from(a[6] as Map) : const {}, source: '/jsonrpc execute_kw');
      }
      if (method == 'execute') {
        return _build(model, rpcMethod, a.sublist(5), const {}, source: '/jsonrpc execute');
      }
    }

    // /web/dataset/call_kw[/model/method]
    if (params['model'] is String && params['method'] is String) {
      return _build(
        params['model'] as String,
        params['method'] as String,
        params['args'] is List ? params['args'] as List : const [],
        params['kwargs'] is Map ? Map<String, Object?>.from(params['kwargs'] as Map) : const {},
        source: '/web/dataset/call_kw',
      );
    }

    // /web/dataset/search_read
    if (params['model'] is String && (params.containsKey('domain') || params.containsKey('fields'))) {
      final kw = <String, Object?>{
        if (params['domain'] != null) 'domain': params['domain'],
        if (params['fields'] != null) 'fields': params['fields'],
        if (params['limit'] != null) 'limit': params['limit'],
        if (params['offset'] != null) 'offset': params['offset'],
        if (params['sort'] != null && '${params['sort']}'.isNotEmpty) 'order': params['sort'],
        if (params['context'] != null) 'context': params['context'],
      };
      return _build(params['model'] as String, 'search_read', const [], kw, source: '/web/dataset/search_read');
    }
    return const OdooConversionResult.failed(
      'Could not recognise this body. Expected execute_kw, /web/dataset/call_kw or /web/dataset/search_read.',
    );
  }

  // --- Python snippets ---------------------------------------------------------

  static OdooConversionResult _fromPython(String text) {
    for (final fn in const ['execute_kw', 'call_kw']) {
      final call = PythonLiteral.callArguments(text, fn);
      if (call == null) continue;
      final p = call.positional;
      if (fn == 'execute_kw') {
        if (p.length < 5) return const OdooConversionResult.failed('execute_kw needs db, uid, password, model and method.');
        final kwargs = p.length > 6 ? p[6] : call.keywords['kw'] ?? call.keywords['kwargs'];
        return _build(
          '${p[3]}',
          '${p[4]}',
          p.length > 5 && p[5] is List ? p[5] as List : const [],
          kwargs is Map ? Map<String, Object?>.from(kwargs) : const {},
          source: 'xmlrpc execute_kw',
        );
      }
      // call_kw(model, method, args, kwargs)
      if (p.length < 2) return const OdooConversionResult.failed('call_kw needs a model and a method.');
      final kwargs = p.length > 3 ? p[3] : call.keywords['kwargs'];
      return _build(
        '${p[0]}',
        '${p[1]}',
        p.length > 2 && p[2] is List ? p[2] as List : const [],
        kwargs is Map ? Map<String, Object?>.from(kwargs) : const {},
        source: 'call_kw',
      );
    }
    final execute = PythonLiteral.callArguments(text, 'execute');
    if (execute != null && execute.positional.length >= 5) {
      final p = execute.positional;
      return _build('${p[3]}', '${p[4]}', p.sublist(5), const {}, source: 'xmlrpc execute');
    }
    return const OdooConversionResult.failed(
      'No execute_kw(...) call found. Paste the line that calls models.execute_kw(db, uid, password, model, method, args, kwargs).',
    );
  }

  // --- shared ------------------------------------------------------------------

  static OdooConversionResult _build(
    String model,
    String method,
    List<dynamic> args,
    Map<String, Object?> kwargs, {
    required String source,
  }) {
    final notes = <String>[];
    final sig = _signatures[method];
    var positional = [...args];
    final ids = <int>[];
    final params = <String, Object?>{};

    final recordset = sig?.recordset ?? _looksLikeRecordsetMethod(method, positional);
    if (recordset) {
      if (positional.isNotEmpty) {
        final first = positional.removeAt(0);
        if (first is List) {
          ids.addAll(first.whereType<num>().map((n) => n.toInt()));
        } else if (first is num) {
          ids.add(first.toInt());
        } else {
          notes.add('The first argument of $method should be a list of record ids; it was ${first.runtimeType}.');
        }
      } else {
        notes.add('$method works on records: add "ids" to the body.');
      }
    }

    if (sig != null) {
      if (positional.length > sig.params.length) {
        notes.add('$method received ${positional.length} positional arguments but takes ${sig.params.length}; extras were dropped.');
      }
      for (var i = 0; i < positional.length && i < sig.params.length; i++) {
        params[sig.params[i]] = positional[i];
      }
      if (sig.note != null) notes.add(sig.note!);
    } else {
      notes.add('"$method" is not a standard method, so its positional arguments cannot be named automatically.');
      for (var i = 0; i < positional.length; i++) {
        params['arg$i'] = positional[i];
        notes.add('Rename "arg$i" to the real parameter name of $method.');
      }
    }

    // Legacy create took one dict; JSON-2 create takes a list of dicts.
    if (method == 'create') {
      final v = params['vals_list'];
      if (v is Map) params['vals_list'] = [v];
    }

    final context = <String, Object?>{};
    kwargs.forEach((k, v) {
      if (k == 'context' && v is Map) {
        context.addAll(Map<String, Object?>.from(v));
      } else if (method == 'name_search' && k == 'args') {
        params['domain'] = v;
      } else if (k == 'sort') {
        params['order'] = v;
      } else {
        params[k] = v;
      }
    });

    return OdooConversionResult.ok(
      OdooConversion(OdooCall(model: model, method: method, ids: ids, params: params, context: context), notes, source),
    );
  }

  /// Unknown methods named like buttons (`action_confirm`, `button_validate`)
  /// are called on records, with the ids as the first argument.
  static bool _looksLikeRecordsetMethod(String method, List<dynamic> args) =>
      method.startsWith('action_') ||
      method.startsWith('button_') ||
      (args.isNotEmpty && args.first is List && (args.first as List).isNotEmpty && (args.first as List).every((e) => e is int));
}
