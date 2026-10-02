import '../../../../core/enums/http_method.dart';
import 'openapi_parser.dart';

/// A request of the collection, reduced to what matching needs.
final class ExistingRequest {
  final int id;
  final String name;
  final HttpMethod method;
  final String url;
  final int? folderId;
  const ExistingRequest({required this.id, required this.name, required this.method, required this.url, required this.folderId});
}

/// An endpoint the spec has and the collection does not.
final class NewEndpoint {
  /// The folder (the OpenAPI tag) it belongs in; null for the collection root.
  final String? folder;
  final OpenApiRequestItem item;
  const NewEndpoint(this.folder, this.item);
}

/// What updating a collection from a spec would do.
final class OpenApiRefreshPlan {
  final List<NewEndpoint> added;

  /// Requests whose endpoint is no longer in the spec.
  final List<ExistingRequest> removed;

  /// Endpoints present on both sides: left exactly as they are, so the
  /// person's edits (headers, bodies, tests) survive.
  final int unchanged;

  const OpenApiRefreshPlan(this.added, this.removed, this.unchanged);

  bool get isEmpty => added.isEmpty && removed.isEmpty;
}

/// Compares a parsed spec with the requests already in a collection. Matching
/// is by method and path with every path parameter treated alike (`{id}`,
/// `{{id}}` and `:id` are the same slot), because that is what identifies an
/// endpoint; names and bodies are the person's to change.
abstract final class OpenApiRefreshPlanner {
  static OpenApiRefreshPlan plan(ParsedOpenApiDocument spec, List<ExistingRequest> existing) {
    final specEndpoints = <String, NewEndpoint>{};
    for (final r in spec.rootRequests) {
      specEndpoints.putIfAbsent(keyOf(r.method, r.url), () => NewEndpoint(null, r));
    }
    for (final folder in spec.folders) {
      for (final r in folder.requests) {
        specEndpoints.putIfAbsent(keyOf(r.method, r.url), () => NewEndpoint(folder.name, r));
      }
    }

    final existingByKey = <String, ExistingRequest>{};
    for (final e in existing) {
      existingByKey.putIfAbsent(keyOf(e.method, e.url), () => e);
    }

    final added = [for (final e in specEndpoints.entries) if (!existingByKey.containsKey(e.key)) e.value];
    // Only requests that look like API calls through the base URL can be "removed from the spec":
    // a hand-made request to some other server is not the spec's business.
    final removed = [
      for (final e in existingByKey.entries)
        if (!specEndpoints.containsKey(e.key) && _isSpecStyle(e.value.url)) e.value,
    ];
    final unchanged = existingByKey.keys.where(specEndpoints.containsKey).length;
    return OpenApiRefreshPlan(added, removed, unchanged);
  }

  /// `GET /pets/{}`: the base URL (a variable or an origin), the query and
  /// every parameter spelling are dropped.
  static String keyOf(HttpMethod method, String url) => '${method.label} ${normalizePath(url)}';

  static String normalizePath(String url) {
    var u = url.trim();
    final q = u.indexOf('?');
    if (q >= 0) u = u.substring(0, q);
    u = u.replaceFirst(RegExp(r'^\{\{[^{}]+\}\}'), '');
    u = u.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+'), '');
    u = u.replaceAll(RegExp(r'\{\{[^{}]+\}\}'), '{}').replaceAll(RegExp(r'\{[^{}/]+\}'), '{}').replaceAll(RegExp(r'/:[^/]+'), '/{}');
    u = u.replaceAll(RegExp(r'/+$'), '');
    return u.isEmpty ? '/' : (u.startsWith('/') ? u : '/$u').toLowerCase();
  }

  static bool _isSpecStyle(String url) => url.trimLeft().startsWith('{{${OpenApiParser.baseUrlVariable}}}');
}
