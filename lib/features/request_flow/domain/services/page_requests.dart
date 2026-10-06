import 'dart:convert';
import '../../../../core/enums/body_type.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../entities/pagination_settings.dart';
import 'json_path_editor.dart';

/// Reads and writes the page parameter of a request: the one thing that changes between the pages of a list. Works
/// on the request as it is saved (before `{{variables}}` are resolved), so a page request goes through exactly the
/// same preparation, signing and checks as any other send.
abstract final class PageRequests {
  /// A value the server sent that holds `{{`, which the variable resolver would take for a variable of the user's:
  /// a hostile or broken response must not be able to pull a secret into the next request.
  static bool looksLikeVariable(String text) => text.contains('{{');

  /// The value of [name] in [location] of [request], resolved; null when the request does not set it.
  static String? read(
    ApiRequestEntity request,
    String name,
    PageParamLocation location,
    VariableResolver resolver,
  ) {
    switch (location) {
      case PageParamLocation.query:
        for (final row in request.queryParams) {
          if (row.enabled && row.key.trim() == name) return resolver.resolve(row.value);
        }
        final resolved = Uri.tryParse(resolver.resolve(request.url));
        return resolved?.queryParametersAll[name]?.lastOrNull;
      case PageParamLocation.body:
        final value = JsonPathEditor.read(_decodeBody(request, resolver)?.document, name);
        return value == null ? null : '$value';
    }
  }

  /// [request] with [name] set to [value] in [location]. A query parameter becomes a row, which replaces a
  /// parameter of the same name in the URL itself; a body value is written into the JSON body (`value` stays a
  /// number or a string as given). Throws a [FormatException] with a sentence for the person when the body
  /// cannot take it.
  static ApiRequestEntity write(
    ApiRequestEntity request,
    String name,
    PageParamLocation location,
    Object value,
    VariableResolver resolver,
  ) {
    switch (location) {
      case PageParamLocation.query:
        final rows = List<KeyValueItem>.of(request.queryParams);
        final index = rows.indexWhere((row) => row.key.trim() == name);
        final text = '$value';
        if (index == -1) {
          rows.add(KeyValueItem(key: name, value: text));
        } else {
          rows[index] = rows[index].copyWith(value: text, enabled: true);
        }
        return request.copyWith(queryParams: rows);
      case PageParamLocation.body:
        final decoded = _decodeBody(request, resolver);
        if (decoded == null) {
          throw const FormatException(
            'The body is not JSON, so the page parameter cannot be written into it. '
            'Use a query parameter, or make the body valid JSON.',
          );
        }
        final document = JsonPathEditor.set(decoded.document, name, value);
        final text = jsonEncode(document);
        final body = request.body;
        return request.copyWith(
          body: decoded.inGraphqlVariables ? body.copyWith(graphqlVariables: text) : body.copyWith(rawText: text),
        );
    }
  }

  /// [request] pointed at [next], the URL the server gave for the following page. The rows that [next] sets itself
  /// are dropped (a row would override the server's value), the others (an API key row) stay.
  static ApiRequestEntity withUrl(ApiRequestEntity request, Uri next) {
    final set = next.queryParametersAll.keys.toSet();
    return request.copyWith(
      url: next.toString(),
      queryParams: [for (final row in request.queryParams) if (!set.contains(row.key.trim())) row],
    );
  }

  /// Whether [a] and [b] are the same server: scheme, host and port.
  static bool sameOrigin(Uri a, Uri b) =>
      a.scheme.toLowerCase() == b.scheme.toLowerCase() && a.host.toLowerCase() == b.host.toLowerCase() && a.port == b.port;

  static ({Object? document, bool inGraphqlVariables})? _decodeBody(ApiRequestEntity request, VariableResolver resolver) {
    final body = request.body;
    final String text;
    final bool graphql;
    switch (body.type) {
      case BodyType.raw:
        text = body.rawText;
        graphql = false;
      case BodyType.graphql:
        text = body.graphqlVariables;
        graphql = true;
      default:
        return null;
    }
    // The text may hold {{variables}} that make it invalid JSON until resolved.
    for (final candidate in [text, resolver.resolve(text)]) {
      try {
        return (document: jsonDecode(candidate), inGraphqlVariables: graphql);
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}
