import 'dart:convert';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';

/// How many records an Odoo `search_read` matches in all, asked of the same server: `search_count` takes the same
/// model and `domain` (and `context`) and answers a number. A `search_read` page gives no total of its own, so
/// this is how the last page is known and the pages can be numbered "2/7".
abstract final class OdooCount {
  /// `…/json/2/<model>/` up to the method, which is what changes.
  static final _search = RegExp(r'^(.*/json/2/[^/?#\s]+/)search_read(?=[/?#]|$)', caseSensitive: false);

  /// The `search_count` request that goes with [request], an Odoo JSON-2 `search_read` over POST with a JSON body;
  /// null for any other request. Everything but the URL's method and the body is the request's own, so the same
  /// host, headers and authentication apply. The body is cut down to the `domain` and `context` that `search_read` had.
  static ApiRequestEntity? requestFor(ApiRequestEntity request, VariableResolver resolver) {
    if (request.method != HttpMethod.post || request.body.type != BodyType.raw) return null;
    final match = _search.firstMatch(request.url);
    if (match == null) return null;
    final body = _decode(request.body.rawText) ?? _decode(resolver.resolve(request.body.rawText));
    if (body is! Map) return null;
    final count = {
      if (body['domain'] != null) 'domain': body['domain'],
      if (body['context'] != null) 'context': body['context'],
    };
    return request.copyWith(
      url: request.url.replaceFirst(_search, '${match[1]}search_count'),
      body: request.body.copyWith(rawText: jsonEncode(count)),
    );
  }

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
