import '../services/odoo_json2.dart';
import '../services/odoo_json_doc.dart';
import '../services/odoo_jsonrpc.dart';
import '../services/odoo_rpc_converter.dart';
import 'odoo_connection.dart';

/// An Odoo request, whichever API it is written for, read into the shape the tools of Studio work in: the model, the
/// method and the JSON-2 body (`ids`, `context`, and the parameters by name). A `call_kw` body is converted with the
/// same table that writes one (see `OdooJsonRpc`), so a check or a fix is the same for both.
final class OdooRequestShape {
  final OdooProtocol protocol;

  /// The model and the method; empty while the URL holds a `{{variable}}` for them.
  final String model;
  final String method;

  /// The body in JSON-2 form. A bare `{{token}}` in it is a placeholder (see [OdooJsonDoc.isToken]).
  final Map<String, Object?> named;
  final OdooJsonDoc doc;

  const OdooRequestShape({
    required this.protocol,
    required this.model,
    required this.method,
    required this.named,
    required this.doc,
  });

  /// The model and the method named by a URL: `/json/2/<model>/<method>` or `/web/dataset/call_kw/<model>/<method>`.
  static ({OdooProtocol protocol, String model, String method})? ofUrl(String url) {
    final json2 = RegExp(r'/json/2/([^/?#\s]+)/([^/?#\s]+)').firstMatch(url);
    if (json2 != null) return (protocol: OdooProtocol.json2, model: _clean(json2[1]!), method: _clean(json2[2]!));
    final rpc = RegExp(r'/web/dataset/call_kw/([^/?#\s]+)/([^/?#\s]+)').firstMatch(url);
    if (rpc != null) return (protocol: OdooProtocol.jsonRpc, model: _clean(rpc[1]!), method: _clean(rpc[2]!));
    if (RegExp(r'/web/dataset/call_kw(?=[/?#]|$)').hasMatch(url)) return (protocol: OdooProtocol.jsonRpc, model: '', method: '');
    return null;
  }

  /// `{{variable}}` in a URL part means "not known yet".
  static String _clean(String part) {
    final decoded = Uri.decodeComponent(part);
    return decoded.contains('{') ? '' : decoded;
  }

  /// True when [url] is a call to Odoo's JSON-2 API or to `call_kw`.
  static bool looksLikeOdoo(String url) => ofUrl(url) != null;

  /// Reads a request from its [url] and raw [bodyText]. [error] says why it cannot be read (a body that is not JSON,
  /// not an Odoo call); [shape] is null then.
  static ({OdooRequestShape? shape, String? error}) read(String url, String bodyText) {
    final target = ofUrl(url);
    if (target == null) {
      return (shape: null, error: 'The URL is not an Odoo call: it has no /json/2/<model>/<method> or /web/dataset/call_kw part.');
    }
    final text = bodyText.trim();
    var doc = const OdooJsonDoc(<String, Object?>{});
    if (text.isNotEmpty) {
      final parsed = OdooJsonDoc.parse(text);
      if (parsed.doc == null) return (shape: null, error: 'The body is not valid JSON: ${parsed.error}');
      doc = parsed.doc!;
    }
    final value = doc.value;
    if (value is! Map) return (shape: null, error: 'The body must be a JSON object.');

    if (target.protocol == OdooProtocol.json2) {
      return (
        shape: OdooRequestShape(
          protocol: OdooProtocol.json2,
          model: target.model,
          method: target.method,
          named: Map<String, Object?>.from(value),
          doc: doc,
        ),
        error: null,
      );
    }

    // call_kw: the model, the method and the arguments are in params.
    final params = value['params'] is Map ? value['params'] as Map : value;
    final model = params['model'] is String ? params['model'] as String : target.model;
    final method = params['method'] is String ? params['method'] as String : target.method;
    if (model.isEmpty || method.isEmpty) {
      return (shape: null, error: 'A call_kw body needs params.model and params.method.');
    }
    final args = params['args'] is List ? params['args'] as List : const [];
    final kwargs = params['kwargs'] is Map ? Map<String, Object?>.from(params['kwargs'] as Map) : <String, Object?>{};
    final converted = OdooRpcConverter.fromCallKw(model, method, args, kwargs);
    final call = converted.conversion!.call;
    final named = <String, Object?>{...call.params};
    final signature = OdooRpcConverter.signatureOf(method);
    // The converter keeps only numbers as ids; a `{{recordId}}` token must survive.
    if (signature?.recordset ?? false) {
      if (args.isNotEmpty) named['ids'] = args.first;
    } else if (call.ids.isNotEmpty) {
      named['ids'] = call.ids;
    }
    if (call.context.isNotEmpty) named['context'] = call.context;
    return (
      shape: OdooRequestShape(protocol: OdooProtocol.jsonRpc, model: model, method: method, named: named, doc: doc),
      error: null,
    );
  }

  /// The body text of this request after [named] was changed (a fix applied), in the form it was written in. [tokens]
  /// is the token table of the changed body when a fix added to it.
  String writeBack(Map<String, Object?> changed, {Map<String, String>? tokens}) {
    final target = OdooJsonDoc(null, tokens ?? doc.tokens);
    if (protocol == OdooProtocol.json2) return target.encode(changed);
    return target.encode(OdooJsonRpc.callBodyOf(model, method, changed));
  }

  /// The ready-made request path of this shape, for a message.
  String get path => protocol == OdooProtocol.json2 ? '/json/2/$model/$method' : OdooJsonRpc.callPath(model, method);

  /// A call of this shape without ids and parameters, for places that only need the model and method.
  OdooCall get bare => OdooCall(model: model, method: method);
}
