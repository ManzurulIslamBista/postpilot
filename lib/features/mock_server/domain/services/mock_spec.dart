import '../../../import_export/domain/services/openapi_parser.dart';
import 'mock_faker.dart';

/// A parameter of an operation: where it is, whether it is required, and its schema.
final class SpecParameter {
  final String name;

  /// `query`, `header`, `path` or `cookie`.
  final String location;
  final bool required;
  final Map<String, dynamic> schema;
  const SpecParameter({required this.name, required this.location, required this.required, required this.schema});
}

/// One declared answer of an operation.
final class SpecResponse {
  /// `200`, `404`, `default` or `2XX`.
  final String status;
  final String description;

  /// Null for an answer without a body.
  final Map<String, dynamic>? schema;

  /// An explicit example from the document (media type `example`, `examples`), else null.
  final Object? example;

  /// The media type the body is declared as (`application/json`); empty when there is no body.
  final String contentType;

  const SpecResponse({required this.status, this.description = '', this.schema, this.example, this.contentType = ''});

  int? get code => int.tryParse(status);
}

final class SpecRequestBody {
  final bool required;
  final Map<String, dynamic>? schema;
  final String contentType;
  const SpecRequestBody({required this.required, required this.schema, required this.contentType});
}

/// One path and method of the document.
final class SpecOperation {
  /// Upper-case: `GET`.
  final String method;

  /// As written in the document: `/users/{id}`.
  final String template;

  /// The path split into segments; a `{name}` segment is a parameter.
  final List<String> segments;
  final String operationId;
  final String summary;
  final List<String> tags;
  final List<SpecParameter> parameters;
  final SpecRequestBody? requestBody;
  final Map<String, SpecResponse> responses;

  const SpecOperation({
    required this.method,
    required this.template,
    required this.segments,
    required this.operationId,
    required this.summary,
    required this.tags,
    required this.parameters,
    required this.requestBody,
    required this.responses,
  });

  /// The route as the mock names it everywhere (list, scenarios, log): parameters as `:name`.
  String get key => '$method ${routePath(segments)}';

  static String routePath(List<String> segments) => '/${segments.map((s) => isParam(s) ? ':${paramName(s)}' : s).join('/')}';

  static bool isParam(String segment) => segment.length > 2 && segment.startsWith('{') && segment.endsWith('}');

  static String paramName(String segment) => segment.substring(1, segment.length - 1);

  /// The lowest 2xx answer declared, else null.
  SpecResponse? get success {
    final codes = responses.values.where((r) => (r.code ?? 0) >= 200 && (r.code ?? 0) < 300).toList()
      ..sort((a, b) => a.code!.compareTo(b.code!));
    if (codes.isNotEmpty) return codes.first;
    return responses['default'] ?? responses['2XX'];
  }

  /// The answer declared for [status]: the exact code, then `4XX`-style, then `default`.
  SpecResponse? responseFor(int status) =>
      responses['$status'] ?? responses['${status ~/ 100}XX'] ?? responses['${status ~/ 100}xx'] ?? responses['default'];

  SpecParameter? parameter(String name, String location) {
    for (final p in parameters) {
      if (p.name == name && p.location == location) return p;
    }
    return null;
  }
}

/// An OpenAPI 3 / Swagger 2 document read for serving: every operation with its parameters, request body and declared
/// answers. The reading (`$ref`, `allOf`, Swagger 2 versus OpenAPI 3) is the importer's own, see [OpenApiParser.view].
final class MockSpec {
  final String title;

  /// The path the document's server lives under (`/api/v3`), empty when it is at the root.
  final String basePath;
  final List<SpecOperation> operations;

  /// Resolves the `$ref`s of the schemas the operations hold.
  final MockSchemaResolver resolver;

  const MockSpec({required this.title, required this.basePath, required this.operations, required this.resolver});

  static const _methods = ['get', 'put', 'post', 'delete', 'patch', 'head', 'options'];

  /// Reads [text] (JSON or YAML). Throws [ImportException] when it is not an OpenAPI or Swagger document.
  factory MockSpec.parse(String text) {
    final view = OpenApiParser.view(text);
    final resolver = _ViewResolver(view);
    final root = view.root;
    final info = root['info'];
    final title = info is Map && info['title'] is String && (info['title'] as String).trim().isNotEmpty ? (info['title'] as String).trim() : 'API';
    final operations = <SpecOperation>[];
    final paths = root['paths'];
    if (paths is Map) {
      for (final entry in paths.entries) {
        final template = '${entry.key}';
        if (template.startsWith('x-') || entry.value is! Map) continue;
        final item = view.resolve((entry.value as Map).cast<String, dynamic>());
        final shared = item['parameters'] is List ? item['parameters'] as List : const [];
        final segments = template.split('/').where((s) => s.isNotEmpty).toList();
        for (final method in _methods) {
          final operation = item[method];
          if (operation is! Map) continue;
          operations.add(_operation(view, template, segments, method, operation.cast<String, dynamic>(), shared));
        }
      }
    }
    return MockSpec(title: title, basePath: _basePath(view.baseUrl), operations: operations, resolver: resolver);
  }

  /// `https://api.example.com/v1/` and `/v1` are both `/v1`; a base URL with `{{variables}}` has no usable path.
  static String _basePath(String baseUrl) {
    if (baseUrl.isEmpty) return '';
    var path = baseUrl;
    final origin = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]*').firstMatch(path);
    if (origin != null) path = path.substring(origin.end);
    final q = path.indexOf('?');
    if (q >= 0) path = path.substring(0, q);
    if (path.contains('{{')) return '';
    path = path.replaceAll(RegExp(r'/+$'), '');
    return path.isEmpty || path.startsWith('/') ? path : '/$path';
  }

  static SpecOperation _operation(
    OpenApiDocumentView view,
    String template,
    List<String> segments,
    String method,
    Map<String, dynamic> operation,
    List<dynamic> shared,
  ) {
    // An operation's parameter overrides a path-level one of the same name and place.
    final merged = <String, Map<String, dynamic>>{};
    for (final raw in [...shared, ...(operation['parameters'] is List ? operation['parameters'] as List : const [])]) {
      if (raw is! Map) continue;
      final p = view.resolve(raw.cast<String, dynamic>());
      if (p.isEmpty) continue;
      merged['${p['in']}:${p['name']}'] = p;
    }
    final parameters = <SpecParameter>[];
    Map<String, dynamic>? swaggerBody;
    var swaggerBodyRequired = false;
    for (final p in merged.values) {
      final location = '${p['in']}';
      if (location == 'body') {
        swaggerBody = p['schema'] is Map ? (p['schema'] as Map).cast<String, dynamic>() : null;
        swaggerBodyRequired = p['required'] == true;
        continue;
      }
      if (location == 'formData') continue;
      // Swagger 2 puts the type on the parameter itself, OpenAPI 3 under `schema`.
      final schema = p['schema'] is Map ? (p['schema'] as Map).cast<String, dynamic>() : {for (final e in p.entries) if (e.key != 'name' && e.key != 'in' && e.key != 'required' && e.key != 'description') e.key: e.value};
      parameters.add(SpecParameter(
        name: '${p['name']}',
        location: location,
        required: p['required'] == true || location == 'path',
        schema: schema,
      ));
    }

    SpecRequestBody? body;
    if (view.isSwagger2) {
      if (swaggerBody != null) {
        final consumes = operation['consumes'] is List ? operation['consumes'] as List : (view.root['consumes'] is List ? view.root['consumes'] as List : const []);
        body = SpecRequestBody(
          required: swaggerBodyRequired,
          schema: swaggerBody,
          contentType: consumes.map((c) => '$c').where((c) => c.contains('json')).firstOrNull ?? 'application/json',
        );
      }
    } else if (operation['requestBody'] is Map) {
      final rb = view.resolve((operation['requestBody'] as Map).cast<String, dynamic>());
      final content = rb['content'] is Map ? (rb['content'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
      final type = _pickMedia(content.keys);
      final media = type == null || content[type] is! Map ? const <String, dynamic>{} : (content[type] as Map).cast<String, dynamic>();
      body = SpecRequestBody(
        required: rb['required'] == true,
        schema: media['schema'] is Map ? (media['schema'] as Map).cast<String, dynamic>() : null,
        contentType: type ?? '',
      );
    }

    final responses = <String, SpecResponse>{};
    final declared = operation['responses'];
    if (declared is Map) {
      for (final entry in declared.entries) {
        if (entry.value is! Map) continue;
        final r = view.resolve((entry.value as Map).cast<String, dynamic>());
        responses['${entry.key}'] = _response(view, '${entry.key}', r, operation);
      }
    }
    final tags = operation['tags'] is List ? (operation['tags'] as List).map((t) => '$t').toList() : const <String>[];
    final id = operation['operationId'];
    final summary = operation['summary'];
    return SpecOperation(
      method: method.toUpperCase(),
      template: template,
      segments: segments,
      operationId: id is String ? id : '',
      summary: summary is String ? summary : '',
      tags: tags,
      parameters: parameters,
      requestBody: body,
      responses: responses,
    );
  }

  static SpecResponse _response(OpenApiDocumentView view, String status, Map<String, dynamic> r, Map<String, dynamic> operation) {
    final description = r['description'] is String ? r['description'] as String : '';
    if (view.isSwagger2) {
      final examples = r['examples'] is Map ? (r['examples'] as Map) : const {};
      final example = examples.entries.where((e) => '${e.key}'.contains('json')).map((e) => e.value).firstOrNull ?? examples.values.firstOrNull;
      final schema = r['schema'] is Map ? (r['schema'] as Map).cast<String, dynamic>() : null;
      return SpecResponse(
        status: status,
        description: description,
        schema: schema,
        example: example,
        contentType: schema == null && example == null ? '' : 'application/json',
      );
    }
    final content = r['content'] is Map ? (r['content'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final type = _pickMedia(content.keys);
    if (type == null || content[type] is! Map) return SpecResponse(status: status, description: description);
    final media = (content[type] as Map).cast<String, dynamic>();
    Object? example = media['example'];
    if (example == null && media['examples'] is Map) {
      final first = (media['examples'] as Map).values.firstOrNull;
      if (first is Map) example = view.resolve(first.cast<String, dynamic>())['value'];
    }
    return SpecResponse(
      status: status,
      description: description,
      schema: media['schema'] is Map ? (media['schema'] as Map).cast<String, dynamic>() : null,
      example: example,
      contentType: type,
    );
  }

  /// JSON first, then text, then whatever comes first.
  static String? _pickMedia(Iterable<String> types) {
    for (final needle in const ['json', 'text/']) {
      for (final type in types) {
        if (type.contains(needle)) return type;
      }
    }
    return types.firstOrNull;
  }
}

final class _ViewResolver implements MockSchemaResolver {
  final OpenApiDocumentView _view;
  const _ViewResolver(this._view);

  @override
  Map<String, dynamic> flatten(Map<String, dynamic> node) => _view.flatten(node);
}
