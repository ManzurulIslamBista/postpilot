/// Plain input of the API docs generator. It carries no secret values:
/// authentication is only ever a summary such as "Bearer Token".
final class ApiDocsModel {
  final String name;
  final String description;
  final List<String> tags;
  final String authSummary;
  final List<ApiDocsField> variables;
  final List<ApiDocsFolder> folders;
  final List<ApiDocsRequest> requests;

  const ApiDocsModel({
    required this.name,
    this.description = '',
    this.tags = const [],
    this.authSummary = '',
    this.variables = const [],
    this.folders = const [],
    this.requests = const [],
  });
}

final class ApiDocsFolder {
  final String name;
  final String description;
  final List<String> tags;
  final List<ApiDocsFolder> folders;
  final List<ApiDocsRequest> requests;

  const ApiDocsFolder({
    required this.name,
    this.description = '',
    this.tags = const [],
    this.folders = const [],
    this.requests = const [],
  });
}

final class ApiDocsRequest {
  final String name;
  final String method;
  final String url;
  final String description;
  final List<String> tags;
  final List<ApiDocsField> queryParams;
  final List<ApiDocsField> headers;
  final ApiDocsBody? body;
  final String authSummary;
  final List<ApiDocsExample> examples;

  const ApiDocsRequest({
    required this.name,
    required this.method,
    required this.url,
    this.description = '',
    this.tags = const [],
    this.queryParams = const [],
    this.headers = const [],
    this.body,
    this.authSummary = '',
    this.examples = const [],
  });
}

final class ApiDocsField {
  final String key;
  final String value;

  /// Where a header the request inherits was set (`folder "Auth"`, `collection "Shop"`); empty for
  /// the request's own rows.
  final String origin;
  const ApiDocsField(this.key, this.value, {this.origin = ''});
}

/// [typeLabel] is what the reader sees ("JSON", "Form Data"); a body holds
/// either [text] (with its [language] for highlighting) or [fields].
final class ApiDocsBody {
  final String typeLabel;
  final String language;
  final String text;
  final String variablesText;
  final List<ApiDocsField> fields;

  const ApiDocsBody({
    required this.typeLabel,
    this.language = '',
    this.text = '',
    this.variablesText = '',
    this.fields = const [],
  });
}

final class ApiDocsExample {
  final String name;
  final int statusCode;
  final String body;
  const ApiDocsExample({required this.name, required this.statusCode, this.body = ''});
}
