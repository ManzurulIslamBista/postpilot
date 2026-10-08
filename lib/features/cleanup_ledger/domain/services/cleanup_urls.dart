// Pure Dart (no Flutter).

/// An Odoo call read off a request URL: which server, which model, which method.
final class OdooEndpoint {
  /// Everything before the API path: `{{odooUrl}}`, or `https://odoo.example.com`.
  final String base;
  final String model;
  final String method;

  /// The call_kw form of Odoo 18 and older (`/web/dataset/call_kw/<model>/<method>`), as against JSON-2 (`/json/2/...`).
  final bool jsonRpc;

  const OdooEndpoint({required this.base, required this.model, required this.method, required this.jsonRpc});

  bool get isCreate => CleanupUrls.createMethods.contains(method);

  /// The same server and model, another method.
  String urlFor(String otherMethod) => jsonRpc
      ? '$base/web/dataset/call_kw/$model/$otherMethod'
      : '$base/json/2/$model/$otherMethod';
}

/// Reading and writing the URLs a cleanup works with. They are templates (`{{baseUrl}}/partners`), never resolved here:
/// the send resolves them, so the environment and the production lock see what they would for any request.
abstract final class CleanupUrls {
  /// The Odoo methods that make records and answer with their ids.
  static const createMethods = {'create', 'copy'};

  static final _json2 = RegExp(r'^(.*?)/json/2/([^/?#]+)/([^/?#]+)');
  static final _callKw = RegExp(r'^(.*?)/web/dataset/call_kw/([^/?#]+)/([^/?#]+)');

  /// The Odoo call [url] makes; null when it is not an Odoo API URL.
  static OdooEndpoint? odoo(String url) {
    final text = url.trim();
    final json2 = _json2.firstMatch(text);
    if (json2 != null) return OdooEndpoint(base: json2[1]!, model: json2[2]!, method: json2[3]!, jsonRpc: false);
    final callKw = _callKw.firstMatch(text);
    if (callKw != null) return OdooEndpoint(base: callKw[1]!, model: callKw[2]!, method: callKw[3]!, jsonRpc: true);
    return null;
  }

  /// [url] without its query and fragment, and without a closing slash.
  static String withoutQuery(String url) {
    var end = url.length;
    for (final mark in const ['?', '#']) {
      final at = url.indexOf(mark);
      if (at != -1 && at < end) end = at;
    }
    var path = url.substring(0, end);
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  /// `DELETE` target for the record [id] a POST to [url] created: the same URL with the id as one more path segment.
  /// The id is percent-encoded, so an id from a response can never add a `{{variable}}` or a path of its own.
  static String restDelete(String url, Object id) => '${withoutQuery(url)}/${Uri.encodeComponent('$id')}';
}
