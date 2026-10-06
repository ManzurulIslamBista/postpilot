import 'dart:convert';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../collections/domain/entities/collection_entity.dart';
import '../../../collections/domain/entities/collection_variable_entity.dart';
import '../../../defaults/domain/entities/defaults_chain.dart';
import '../../../defaults/domain/services/defaults_resolver.dart';
import '../../../defaults/domain/services/header_inheritance.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import 'collection_tree.dart';

final class OpenApiExport {
  final String text;

  /// Operations written to the document.
  final int operations;

  /// Requests left out: no URL, or the same method+path as an earlier request
  /// (an OpenAPI path holds one operation per method).
  final int skipped;

  const OpenApiExport({required this.text, required this.operations, required this.skipped});
}

/// Serializes a collection as an OpenAPI 3.0.3 JSON document: the mirror image
/// of `OpenApiParser`, so importing the result back gives the same requests.
///
/// * Servers: a leading `{{baseUrl}}`-style variable that holds an absolute URL
///   (as `OpenApiParser` writes it), or the origin of an absolute URL, becomes a
///   server; the most used one is `servers[0]`, and an operation on another
///   origin carries its own `servers` override. `{{variables}}` in the origin
///   are resolved from the collection's enabled variables; a request whose
///   origin can't be resolved is written path-only.
/// * Paths: query string and fragment are dropped; `{{var}}`, `{var}` and
///   Postman-style `:var` segments become path parameters.
/// * Operations: enabled query params and headers are `required`, disabled
///   ones optional; `Accept`, `Content-Type` and `Authorization` headers are
///   never parameters (the spec ignores them). A body becomes a
///   `requestBody` for POST/PUT/PATCH only (other methods' bodies have no
///   defined semantics and validators reject them); JSON bodies carry an
///   inferred schema and the body as example.
/// * Security: auth types map to security schemes (`bearerAuth`, `basicAuth`,
///   `digestAuth`, `apiKey...`, `oauth2Auth`, ...); the collection's auth is the
///   document-wide `security`, and requests only override it when they differ.
///   The secrets of an auth type (tokens, passwords, keys) never reach the
///   schemes; header, query and body values are written as examples, as they are.
abstract final class OpenApiExporter {
  static const openApiVersion = '3.0.3';

  static OpenApiExport export({
    required String collectionName,
    required List<FolderEntity> folders,
    required List<ApiRequestEntity> requests,
    List<CollectionVariableEntity> variables = const [],
    RequestAuth? collectionAuth,
    DefaultsTree? defaults,
  }) =>
      _Exporter(
        collectionName: collectionName,
        folders: folders,
        requests: requests,
        variables: {for (final v in variables) if (v.enabled) v.key: v.value},
        collectionAuth: collectionAuth,
        defaults: defaults,
      ).run();
}

final class _Exporter {
  static const _indent = JsonEncoder.withIndent('  ');
  static final _absoluteUrl = RegExp(r'^https?://', caseSensitive: false);
  static final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
  static final _leadingVariable = RegExp(r'^\{\{([\w.$-]+)\}\}');
  static final _origin = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*://[^/]*)(.*)$');
  static final _pathParameter = RegExp(r'\{([^{}/]+)\}');
  static final _colonSegment = RegExp(r'^:([A-Za-z_]\w*)$');
  static final _integer = RegExp(r'^-?(0|[1-9]\d*)$');
  static final _decimal = RegExp(r'^-?(0|[1-9]\d*)\.\d+$');
  static const _reservedHeaders = {'accept', 'content-type', 'authorization'};
  static const _bodyMethods = {HttpMethod.post, HttpMethod.put, HttpMethod.patch};

  final String collectionName;
  final List<FolderEntity> folders;
  final List<ApiRequestEntity> requests;
  final Map<String, String> variables;
  final RequestAuth? collectionAuth;

  /// What the collection and its folders pass down: a request that inherits takes the nearest
  /// folder's auth rather than the collection's, and carries the headers they pass down as parameters.
  final DefaultsTree? defaults;

  final _schemes = <String, Map<String, dynamic>>{};
  final _schemeKeysByDefinition = <String, String>{};
  final _operationIds = <String>{};
  final _pathsByShape = <String, String>{};

  _Exporter({
    required this.collectionName,
    required this.folders,
    required this.requests,
    required this.variables,
    required this.collectionAuth,
    this.defaults,
  });

  OpenApiExport run() {
    final planned = <({String? tag, ApiRequestEntity request, _Target target})>[];
    var skipped = 0;
    for (final (:folder, :request) in CollectionTree.ordered(folders, requests)) {
      final target = _Target.parse(request.url, variables);
      if (target == null) {
        skipped++;
        continue;
      }
      planned.add((tag: folder, request: request, target: target));
    }

    final servers = _serversByUse(planned.map((p) => p.target.server));
    final globalScheme = _schemeOf(collectionAuth);
    final paths = <String, Map<String, dynamic>>{};
    final tags = <String>[];
    var operations = 0;
    for (final (:tag, :request, :target) in planned) {
      final path = _canonicalPath(target.path);
      final item = paths.putIfAbsent(path, () => {});
      if (item.containsKey(request.method.name)) {
        skipped++;
        continue;
      }
      if (tag != null && !tags.contains(tag)) tags.add(tag);
      item[request.method.name] = _operation(request, target, path, tag, servers.firstOrNull, globalScheme);
      operations++;
    }

    final document = <String, dynamic>{
      'openapi': OpenApiExporter.openApiVersion,
      'info': {
        'title': collectionName.trim().isEmpty ? 'API' : collectionName.trim(),
        'version': '1.0.0',
        'description': 'Exported from PostPilot.',
      },
      if (servers.isNotEmpty) 'servers': [for (final s in servers) {'url': s}],
      if (tags.isNotEmpty) 'tags': [for (final t in tags) {'name': t}],
      if (globalScheme != null) 'security': [_requirement(globalScheme)],
      'paths': paths,
      if (_schemes.isNotEmpty) 'components': {'securitySchemes': _schemes},
    };
    return OpenApiExport(text: _indent.convert(document), operations: operations, skipped: skipped);
  }

  // ---- servers and paths --------------------------------------------------

  List<String> _serversByUse(Iterable<String?> servers) {
    final counts = <String, int>{};
    for (final server in servers) {
      if (server != null) counts.update(server, (n) => n + 1, ifAbsent: () => 1);
    }
    final appearance = counts.keys.toList();
    // `List.sort` isn't stable, so ties are broken by first appearance explicitly.
    return [...appearance]..sort((a, b) {
        final byUse = counts[b]!.compareTo(counts[a]!);
        return byUse != 0 ? byUse : appearance.indexOf(a).compareTo(appearance.indexOf(b));
      });
  }

  /// `/users/{id}` and `/users/{userId}` are the same path to OpenAPI, and two
  /// spellings of it would be invalid, so later ones adopt the first spelling.
  String _canonicalPath(String path) => _pathsByShape.putIfAbsent(path.replaceAll(_pathParameter, '{}'), () => path);

  // ---- operations ---------------------------------------------------------

  Map<String, dynamic> _operation(
    ApiRequestEntity request,
    _Target target,
    String path,
    String? tag,
    String? primaryServer,
    _SchemeRef? globalScheme,
  ) {
    final inherited = defaults == null ? null : DefaultsResolver.resolve(defaults!.chainFor(request.folderId));
    final inheritedAuth = inherited?.auth ?? collectionAuth;
    final auth = request.auth.resolveInherited(inheritedAuth);
    final headers = HeaderInheritance.materialize(inherited?.headerRows ?? const [], request.headers);
    final parameters = _parameters(request, headers, target, path, auth);
    final body = _requestBody(request, headers);
    final security = _operationSecurity(request.auth, globalScheme, inheritedAuth);
    return {
      'tags': ?(tag == null ? null : [tag]),
      'summary': request.name.trim().isEmpty ? 'Untitled request' : request.name.trim(),
      'operationId': _operationId(request, path),
      if (parameters.isNotEmpty) 'parameters': parameters,
      'requestBody': ?body,
      'responses': {
        'default': {'description': 'Response'},
      },
      'security': ?security,
      if (target.server != null && target.server != primaryServer)
        'servers': [
          {'url': target.server},
        ],
    };
  }

  String _operationId(ApiRequestEntity request, String path) {
    var base = _camelCase(request.name);
    if (base.isEmpty) base = _camelCase('${request.method.name} $path');
    if (base.isEmpty) base = request.method.name;
    var id = base;
    for (var n = 2; !_operationIds.add(id); n++) {
      id = '$base$n';
    }
    return id;
  }

  static String _camelCase(String text) {
    final words = [for (final m in RegExp(r'[A-Za-z0-9]+').allMatches(text)) m[0]!];
    if (words.isEmpty) return '';
    final camel = words.first.toLowerCase() +
        words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join();
    return RegExp(r'^\d').hasMatch(camel) ? 'op$camel' : camel;
  }

  // ---- parameters ---------------------------------------------------------

  /// [headers] are the request's own rows with the ones it inherits written in (see `HeaderInheritance.materialize`).
  List<Map<String, dynamic>> _parameters(
    ApiRequestEntity request,
    List<KeyValueItem> headers,
    _Target target,
    String path,
    RequestAuth auth,
  ) {
    final parameters = <Map<String, dynamic>>[];
    final seen = <String>{};
    void add(Map<String, dynamic> parameter) {
      if (seen.add('${parameter['in']}:${parameter['name']}')) parameters.add(parameter);
    }

    final apiKeyName = auth.type == AuthType.apiKey ? auth.apiKeyName.toLowerCase() : null;
    final apiKeyLocation = auth.apiKeyLocation == ApiKeyLocation.query ? 'query' : 'header';

    for (final match in _pathParameter.allMatches(path)) {
      add({
        'name': match[1],
        'in': 'path',
        'required': true,
        'schema': {'type': 'string'},
      });
    }
    bool coveredByAuth(String location, String name) => apiKeyName == name.toLowerCase() && apiKeyLocation == location;

    for (final param in request.queryParams) {
      if (param.key.isEmpty || coveredByAuth('query', param.key)) continue;
      add(_parameter('query', param.key, param.value, required: param.enabled, infer: true));
    }
    for (final (name, value) in target.query) {
      if (!coveredByAuth('query', name)) add(_parameter('query', name, value, required: true, infer: true));
    }
    for (final header in headers) {
      final name = header.key.trim();
      if (name.isEmpty || _reservedHeaders.contains(name.toLowerCase()) || coveredByAuth('header', name)) continue;
      add(_parameter('header', name, header.value, required: header.enabled, infer: false));
    }
    return parameters;
  }

  Map<String, dynamic> _parameter(String location, String name, String value, {required bool required, required bool infer}) {
    final typed = infer ? _typedValue(value) : value;
    return {
      'name': name,
      'in': location,
      'required': required,
      'schema': {'type': typed is int ? 'integer' : typed is double ? 'number' : typed is bool ? 'boolean' : 'string'},
      if (value.isNotEmpty) 'example': typed,
    };
  }

  /// An integer, decimal or boolean written as text keeps its type; anything
  /// else, `{{variables}}` included, stays a string. A digit run that does not
  /// fit an int (an account number, a snowflake id) or a decimal that is not a
  /// finite double is an identifier rather than a quantity: it stays the
  /// exact text instead of failing the whole export.
  Object _typedValue(String value) {
    if (_integer.hasMatch(value)) {
      final number = int.tryParse(value);
      // On the web an int past 2^53 parses but loses digits; only exact ones count.
      return number != null && '$number' == value ? number : value;
    }
    if (_decimal.hasMatch(value)) {
      final number = double.tryParse(value);
      return number != null && number.isFinite ? number : value;
    }
    if (value == 'true' || value == 'false') return value == 'true';
    return value;
  }

  // ---- request body -------------------------------------------------------

  Map<String, dynamic>? _requestBody(ApiRequestEntity request, List<KeyValueItem> headers) {
    if (!_bodyMethods.contains(request.method)) return null;
    final body = request.body;
    switch (body.type) {
      case BodyType.none:
        return null;
      case BodyType.raw:
        return body.rawText.trim().isEmpty ? null : _rawBody(request, headers);
      case BodyType.urlEncoded:
        return _formBody('application/x-www-form-urlencoded', body.urlEncodedFields);
      case BodyType.formData:
        return _formBody('multipart/form-data', body.formFields);
      case BodyType.graphql:
        final parsedVariables = _decodeJson(body.graphqlVariables);
        return _content('application/json', {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
            'variables': {'type': 'object'},
          },
        }, {
          'query': body.graphqlQuery,
          'variables': parsedVariables is Map ? parsedVariables : const {},
        });
    }
  }

  Map<String, dynamic> _rawBody(ApiRequestEntity request, List<KeyValueItem> headers) {
    final body = request.body;
    final mediaType = _declaredMediaType(headers) ?? body.rawContentType.mimeType;
    final json = mediaType.contains('json') ? _decodeJson(body.rawText) : null;
    if (json != null) return _content(mediaType, _schemaOf(json), json);
    return _content(mediaType, {'type': 'string'}, body.rawText);
  }

  /// The media type of an enabled `Content-Type` header, without parameters.
  String? _declaredMediaType(List<KeyValueItem> headers) {
    for (final h in headers) {
      if (h.enabled && h.key.toLowerCase() == 'content-type') {
        final essence = h.value.split(';').first.trim().toLowerCase();
        if (essence.isNotEmpty && !essence.contains('{{')) return essence;
      }
    }
    return null;
  }

  Map<String, dynamic>? _formBody(String mediaType, List<KeyValueItem> fields) {
    final enabled = fields.where((f) => f.enabled && f.key.isNotEmpty).toList();
    if (enabled.isEmpty) return null;
    return _content(
      mediaType,
      {
        'type': 'object',
        'properties': {for (final f in enabled) f.key: {'type': 'string'}},
      },
      {for (final f in enabled) f.key: f.value},
    );
  }

  Map<String, dynamic> _content(String mediaType, Map<String, dynamic> schema, Object example) => {
        'required': true,
        'content': {
          mediaType: {'schema': schema, 'example': example},
        },
      };

  /// The decoded JSON of [text], or null when it isn't JSON. A body that is
  /// only invalid because of a bare `{{variable}}` (`{"id": {{userId}}}`) is
  /// read with that variable as a string.
  Object? _decodeJson(String text) {
    for (final candidate in [text, _quoteBareVariables(text)]) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded != null) return decoded;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  static String _quoteBareVariables(String text) {
    final out = StringBuffer();
    var inString = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        out.write(char);
        if (char == r'\' && i + 1 < text.length) {
          out.write(text[++i]);
        } else if (char == '"') {
          inString = false;
        }
      } else if (char == '"') {
        inString = true;
        out.write(char);
      } else if (text.startsWith('{{', i) && text.indexOf('}}', i + 2) != -1) {
        final end = text.indexOf('}}', i + 2) + 2;
        out.write('"${text.substring(i, end)}"');
        i = end - 1;
      } else {
        out.write(char);
      }
    }
    return out.toString();
  }

  static Map<String, dynamic> _schemaOf(Object? value) => switch (value) {
        Map() => {
            'type': 'object',
            if (value.isNotEmpty) 'properties': {for (final e in value.entries) '${e.key}': _schemaOf(e.value)},
          },
        List() => {'type': 'array', 'items': value.isEmpty ? <String, dynamic>{} : _schemaOf(value.first)},
        String() => {'type': 'string'},
        int() => {'type': 'integer'},
        num() => {'type': 'number'},
        bool() => {'type': 'boolean'},
        _ => <String, dynamic>{},
      };

  // ---- security -----------------------------------------------------------

  /// Null when the request follows the document-wide `security`; `[]` for an
  /// explicit "no auth" where a default exists. A request that inherits is judged by the auth it
  /// inherits ([inheritedAuth]: the nearest folder's, else the collection's), which is
  /// the document-wide one unless a folder sets another.
  List<Map<String, List<String>>>? _operationSecurity(RequestAuth auth, _SchemeRef? globalScheme, RequestAuth? inheritedAuth) {
    final effective = auth.type == AuthType.inherit ? inheritedAuth : auth;
    if (effective == null) return null;
    switch (effective.type) {
      case AuthType.inherit:
        return null;
      case AuthType.none:
        return globalScheme == null ? null : const [];
      default:
        final scheme = _schemeOf(effective);
        if (scheme == null || scheme == globalScheme) return null;
        return [_requirement(scheme)];
    }
  }

  Map<String, List<String>> _requirement(_SchemeRef scheme) => {scheme.key: scheme.scopes};

  _SchemeRef? _schemeOf(RequestAuth? auth) {
    if (auth == null) return null;
    switch (auth.type) {
      case AuthType.none:
      case AuthType.inherit:
        return null;
      case AuthType.bearer:
        return _register('bearerAuth', {'type': 'http', 'scheme': 'bearer'});
      case AuthType.jwtBearer:
        return _register('jwtAuth', {'type': 'http', 'scheme': 'bearer', 'bearerFormat': 'JWT'});
      case AuthType.basic:
        return _register('basicAuth', {'type': 'http', 'scheme': 'basic'});
      case AuthType.digest:
        return _register('digestAuth', {'type': 'http', 'scheme': 'digest'});
      case AuthType.apiKey:
        if (auth.apiKeyName.trim().isEmpty) return null;
        return _register('apiKeyAuth', {
          'type': 'apiKey',
          'name': auth.apiKeyName.trim(),
          'in': auth.apiKeyLocation == ApiKeyLocation.query ? 'query' : 'header',
        });
      case AuthType.awsSignatureV4:
        return _register('awsSigV4Auth', {
          'type': 'apiKey',
          'name': 'Authorization',
          'in': 'header',
          'x-amazon-apigateway-authtype': 'awsSigv4',
        });
      case AuthType.oauth2:
        return _oauth2Scheme(auth);
    }
  }

  _SchemeRef _oauth2Scheme(RequestAuth auth) {
    final scopes = auth.oauth2Scope.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final scopeMap = {for (final s in scopes) s: ''};
    final tokenUrl = _resolveVariables(auth.oauth2AccessTokenUrl);
    final flow = switch (auth.oauth2GrantType) {
      OAuth2GrantType.clientCredentials => {
          'clientCredentials': {'tokenUrl': tokenUrl, 'scopes': scopeMap},
        },
      OAuth2GrantType.password => {
          'password': {'tokenUrl': tokenUrl, 'scopes': scopeMap},
        },
      OAuth2GrantType.authorizationCodePkce => {
          'authorizationCode': {
            'authorizationUrl': _resolveVariables(auth.oauth2AuthorizationUrl),
            'tokenUrl': tokenUrl,
            'scopes': scopeMap,
          },
        },
    };
    return _register('oauth2Auth', {'type': 'oauth2', 'flows': flow}, scopes: scopes);
  }

  /// Registers a security scheme and returns its reference. The same
  /// definition always gets the same key; a different definition that wants a
  /// taken key gets a numbered one (`oauth2Auth2`).
  _SchemeRef _register(String baseKey, Map<String, dynamic> definition, {List<String> scopes = const []}) {
    final fingerprint = jsonEncode(definition);
    final existing = _schemeKeysByDefinition[fingerprint];
    if (existing != null) return _SchemeRef(existing, scopes);
    var key = baseKey;
    for (var n = 2; _schemes.containsKey(key); n++) {
      key = '$baseKey$n';
    }
    _schemes[key] = definition;
    _schemeKeysByDefinition[fingerprint] = key;
    return _SchemeRef(key, scopes);
  }

  String _resolveVariables(String text) => _resolveWith(variables, text);
}

/// A security scheme plus the scopes one requirement asks of it.
final class _SchemeRef {
  final String key;
  final List<String> scopes;
  const _SchemeRef(this.key, this.scopes);

  @override
  bool operator ==(Object other) => other is _SchemeRef && other.key == key && other.scopes.join(' ') == scopes.join(' ');

  @override
  int get hashCode => Object.hash(key, scopes.join(' '));
}

/// Where a request goes: the server it is on (null when unknown), the path
/// template and the query pairs written into its URL.
final class _Target {
  final String? server;
  final String path;
  final List<(String, String)> query;
  const _Target(this.server, this.path, this.query);

  static _Target? parse(String rawUrl, Map<String, String> variables) {
    var url = rawUrl.trim();
    final fragment = url.indexOf('#');
    if (fragment >= 0) url = url.substring(0, fragment);
    if (url.isEmpty) return null;
    final questionMark = url.indexOf('?');
    final address = questionMark >= 0 ? url.substring(0, questionMark) : url;
    final queryText = questionMark >= 0 ? url.substring(questionMark + 1) : '';

    String? server;
    var rest = address;
    final lead = _Exporter._leadingVariable.firstMatch(address);
    if (lead != null) {
      // A URL that opens with a variable: that variable is the base URL.
      rest = address.substring(lead.end);
      final value = variables[lead[1]];
      if (value != null) {
        final resolved = _resolveWith(variables, value);
        if (_Exporter._absoluteUrl.hasMatch(resolved)) {
          server = _serverOf(resolved);
        } else {
          rest = '$resolved$rest';
        }
      }
    } else {
      // Like the request sender, no scheme means http://.
      final absolute = _Exporter._scheme.hasMatch(address) || address.startsWith('/') ? address : 'http://$address';
      final origin = _Exporter._origin.firstMatch(absolute);
      if (origin == null) {
        rest = absolute;
      } else {
        server = _serverOf(_resolveWith(variables, origin[1]!));
        rest = origin[2]!;
      }
    }

    return _Target(server, _pathTemplateOf(rest), _queryOf(queryText));
  }

  /// Null when a `{{variable}}` is left in it: that isn't a URL.
  static String? _serverOf(String url) {
    final trimmed = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    return trimmed.contains('{{') ? null : trimmed;
  }

  static String _pathTemplateOf(String rest) {
    var path = rest.isEmpty ? '/' : rest;
    if (!path.startsWith('/')) path = '/$path';
    path = path.replaceAllMapped(AppConstants.variablePattern, (m) => '{${_parameterName(m[1]!)}}');
    final segments = path.split('/').map((s) {
      final colon = _Exporter._colonSegment.firstMatch(s);
      return colon == null ? s : '{${colon[1]}}';
    });
    return segments.join('/');
  }

  static String _parameterName(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  static List<(String, String)> _queryOf(String text) => [
        for (final pair in text.split('&'))
          if (pair.isNotEmpty && !pair.startsWith('='))
            (_decode(pair.split('=').first), _decode(pair.contains('=') ? pair.substring(pair.indexOf('=') + 1) : '')),
      ];

  static String _decode(String text) {
    try {
      return Uri.decodeQueryComponent(text);
    } catch (_) {
      return text;
    }
  }
}

/// Substitutes `{{name}}` with the variable's value, following variables that
/// hold variables a few levels deep; unknown names stay as written.
String _resolveWith(Map<String, String> variables, String text, [int depth = 0]) {
  if (depth > 5) return text;
  return text.replaceAllMapped(AppConstants.variablePattern, (m) {
    final value = variables[m[1]];
    return value == null ? m[0]! : _resolveWith(variables, value, depth + 1);
  });
}
