import 'dart:convert';
import 'package:yaml/yaml.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/entities/request_body.dart';

final class OpenApiRequestItem {
  final String name;
  final HttpMethod method;
  final String url;
  final List<KeyValueItem> headers;
  final List<KeyValueItem> queryParams;
  final RequestBody body;
  final RequestAuth auth;
  const OpenApiRequestItem({
    required this.name,
    required this.method,
    required this.url,
    required this.headers,
    required this.queryParams,
    required this.body,
    required this.auth,
  });
}

final class OpenApiFolder {
  final String name;
  final List<OpenApiRequestItem> requests;
  const OpenApiFolder(this.name, this.requests);
}

final class ParsedOpenApiDocument {
  final String name;

  /// What every request's `{{baseUrl}}` stands for; empty when the document
  /// declares no server, and possibly relative (`/api/v3`).
  final String baseUrl;
  final List<OpenApiRequestItem> rootRequests;
  final List<OpenApiFolder> folders;
  const ParsedOpenApiDocument({
    required this.name,
    required this.baseUrl,
    required this.rootRequests,
    required this.folders,
  });
}

/// Parses an OpenAPI 3.x or Swagger 2.0 document (JSON or YAML) into one
/// request per path+method, with each operation's first tag becoming a
/// folder. Every URL starts with `{{baseUrl}}` (see
/// [ParsedOpenApiDocument.baseUrl]) so the server is edited once, not per
/// request, and a spec with a relative or missing server still imports.
/// Bodies are best-effort: an explicit example wins, otherwise a skeleton is
/// built from the schema with placeholder values, bounded so cyclic or
/// densely cross-linked schemas can't blow up. Anything the app can't
/// represent (cookie API keys, file fields, `trace`, external `$ref`s, ...)
/// is skipped rather than rejected — a partially-imported API beats a failed
/// import.
final class OpenApiParser {
  static const baseUrlVariable = 'baseUrl';

  static final _pathParam = RegExp(r'\{([^{}/]+)\}');
  static final _nonWord = RegExp(r'\W');
  static final _localHost = RegExp(
    r'^(localhost|127(\.\d+){3}|10(\.\d+){3}|192\.168(\.\d+){2}|172\.(1[6-9]|2\d|3[01])(\.\d+){2}|\[::1\]|0\.0\.0\.0)(:\d+)?$',
    caseSensitive: false,
  );
  static const _ignoredHeaderParams = {'accept', 'content-type', 'authorization'};
  static const _jsonIndent = JsonEncoder.withIndent('  ');

  /// Marks a spot where an example had to stop expanding (a `$ref` cycle or a
  /// cap hit); parents leave it out instead of emitting `null`.
  static const _cut = Object();

  final Map<String, dynamic> _root;
  final bool _isSwagger2;

  OpenApiParser._(this._root) : _isSwagger2 = '${_root['swagger'] ?? ''}'.startsWith('2');

  static ParsedOpenApiDocument parse(String text) {
    final root = _decode(text);
    final version = '${root['openapi'] ?? root['swagger'] ?? ''}';
    if (!version.startsWith('3') && !version.startsWith('2')) {
      throw const ImportException('no "openapi: 3.x" or "swagger: 2.0" version field found.');
    }
    return OpenApiParser._(root)._parse();
  }

  static Map<String, dynamic> _decode(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw const ImportException('the document is empty.');
    final root = trimmed.startsWith('{') ? jsonDecode(trimmed) : _plain(loadYaml(trimmed));
    if (root is! Map<String, dynamic>) throw const ImportException('expected a top-level object.');
    return root;
  }

  static dynamic _plain(dynamic node) => switch (node) {
        Map() => <String, dynamic>{for (final e in node.entries) '${e.key}': _plain(e.value)},
        List() => node.map(_plain).toList(),
        _ => node,
      };

  ParsedOpenApiDocument _parse() {
    final name = _str(_map(_root['info'])['title']) ?? 'Imported API';
    final rootRequests = <OpenApiRequestItem>[];
    final byTag = <String, List<OpenApiRequestItem>>{};

    for (final entry in _map(_root['paths']).entries) {
      if (entry.key.startsWith('x-')) continue;
      final pathItem = _resolve(_map(entry.value));
      final pathParams = _list(pathItem['parameters']);
      for (final method in HttpMethod.values) {
        final operation = pathItem[method.name];
        if (operation is! Map) continue;
        final request = _requestOf(entry.key, method, _map(operation), pathParams);
        final tags = _list(operation['tags']);
        final tag = tags.isEmpty ? null : _str(tags.first);
        (tag == null ? rootRequests : byTag.putIfAbsent(tag, () => [])).add(request);
      }
    }

    final folders = [for (final tag in _orderedTags(byTag.keys)) OpenApiFolder(tag, byTag[tag]!)];
    return ParsedOpenApiDocument(name: name, baseUrl: _baseUrl(), rootRequests: rootRequests, folders: folders);
  }

  /// Folders follow the document's top-level `tags` order where declared,
  /// then first appearance.
  List<String> _orderedTags(Iterable<String> present) {
    final declared = _list(_root['tags']).map((t) => _str(_map(t)['name'])).whereType<String>().toList();
    return [...declared.where(present.contains), ...present.where((t) => !declared.contains(t))];
  }

  String _baseUrl() {
    if (_isSwagger2) {
      final host = _str(_root['host']);
      final basePath = _str(_root['basePath']) ?? '';
      if (host == null) return _trimSlash(basePath);
      return _trimSlash('${_swagger2Scheme(host)}://$host$basePath');
    }
    final servers = _list(_root['servers']);
    if (servers.isEmpty) return '';
    final server = _map(servers.first);
    final variables = _map(server['variables']);
    final url = (_str(server['url']) ?? '').replaceAllMapped(_pathParam, (m) {
      final fallback = _map(variables[m[1]])['default'];
      return fallback == null ? _placeholder(m[1]!) : '$fallback';
    });
    return _trimSlash(url);
  }

  /// Swagger 2 only lists the schemes an API is served over. Unless exactly
  /// one of http/https is declared, a local dev server is plain http and
  /// anything else is https.
  String _swagger2Scheme(String host) {
    final declared = _list(_root['schemes']).where((s) => s == 'http' || s == 'https').toList();
    if (declared.length == 1) return '${declared.single}';
    return _localHost.hasMatch(host) ? 'http' : 'https';
  }

  OpenApiRequestItem _requestOf(
    String path,
    HttpMethod method,
    Map<String, dynamic> operation,
    List<dynamic> pathLevelParams,
  ) {
    final params = _mergedParameters(pathLevelParams, _list(operation['parameters']));
    final headers = <KeyValueItem>[];
    final queryParams = <KeyValueItem>[];
    for (final p in params) {
      final item = KeyValueItem(key: _str(p['name']) ?? '', value: _paramValue(p), enabled: p['required'] == true);
      switch (p['in']) {
        case 'query':
          queryParams.add(item);
        case 'header':
          if (!_ignoredHeaderParams.contains(item.key.toLowerCase())) headers.add(item);
      }
    }
    final (body, contentType) = _isSwagger2 ? _swagger2BodyOf(operation, params) : _bodyOf(operation);
    if (contentType != null) headers.add(KeyValueItem(key: 'Content-Type', value: contentType));
    return OpenApiRequestItem(
      name: _str(operation['summary']) ?? _str(operation['operationId']) ?? '${method.label} $path',
      method: method,
      url: '{{$baseUrlVariable}}${path.replaceAllMapped(_pathParam, (m) => _placeholder(m[1]!))}',
      headers: headers,
      queryParams: queryParams,
      body: body,
      auth: _authOf(operation),
    );
  }

  /// Operation-level parameters override path-level ones with the same
  /// name+location, per spec.
  List<Map<String, dynamic>> _mergedParameters(List<dynamic> pathLevel, List<dynamic> operationLevel) {
    final merged = <String, Map<String, dynamic>>{};
    for (final raw in [...pathLevel, ...operationLevel]) {
      final p = _resolve(_map(raw));
      if (p.isEmpty) continue;
      merged['${p['in']}:${p['name']}'] = p;
    }
    return merged.values.toList();
  }

  String _paramValue(Map<String, dynamic> p) {
    final schema = _flatten(_map(p['schema']));
    final value = p['example'] ??
        p['x-example'] ??
        p['default'] ??
        schema['example'] ??
        schema['default'] ??
        _first(p['enum']) ??
        _first(schema['enum']) ??
        _firstExampleValue(p['examples']);
    return value == null ? '' : _text(value);
  }

  /// The second value is a `Content-Type` to send explicitly: set only when a
  /// raw body's [RawContentType] can't express the declared media type.
  (RequestBody, String?) _bodyOf(Map<String, dynamic> operation) {
    final content = _map(_resolve(_map(operation['requestBody']))['content']);
    if (content.isEmpty) return (RequestBody.empty, null);
    final mediaType = _pickMediaType(content.keys);
    final media = _map(content[mediaType]);
    final schema = _map(media['schema']);
    if (mediaType.contains('x-www-form-urlencoded')) {
      return (RequestBody(type: BodyType.urlEncoded, urlEncodedFields: _formFieldsOf(schema)), null);
    }
    if (mediaType.contains('multipart')) {
      return (RequestBody(type: BodyType.formData, formFields: _formFieldsOf(schema)), null);
    }
    final example = media['example'] ?? _firstExampleValue(media['examples']) ?? _example(schema);
    return _rawBody(mediaType, example);
  }

  (RequestBody, String?) _swagger2BodyOf(Map<String, dynamic> operation, List<Map<String, dynamic>> params) {
    final declared = operation['consumes'] is List ? operation['consumes'] : _root['consumes'];
    final consumes = _list(declared).map((c) => '$c').toList();
    final formParams = params.where((p) => p['in'] == 'formData').toList();
    if (formParams.isNotEmpty) {
      final hasFile = formParams.any((p) => p['type'] == 'file');
      final fields = [
        for (final p in formParams)
          if (p['type'] != 'file') KeyValueItem(key: _str(p['name']) ?? '', value: _paramValue(p)),
      ];
      final body = hasFile || consumes.any((c) => c.contains('multipart'))
          ? RequestBody(type: BodyType.formData, formFields: fields)
          : RequestBody(type: BodyType.urlEncoded, urlEncodedFields: fields);
      return (body, null);
    }
    final bodyParam = params.where((p) => p['in'] == 'body').toList();
    if (bodyParam.isEmpty) return (RequestBody.empty, null);
    final schema = _map(bodyParam.first['schema']);
    final mediaType = consumes.isEmpty ? 'application/json' : _pickMediaType(consumes);
    return _rawBody(mediaType, bodyParam.first['x-example'] ?? _example(schema));
  }

  static String _pickMediaType(Iterable<String> mediaTypes) {
    for (final needle in ['json', 'x-www-form-urlencoded', 'multipart']) {
      for (final type in mediaTypes) {
        if (type.contains(needle)) return type;
      }
    }
    return mediaTypes.first;
  }

  static (RequestBody, String?) _rawBody(String mediaType, dynamic example) {
    final contentType = switch (mediaType) {
      final t when t.contains('json') => RawContentType.json,
      final t when t.contains('xml') => RawContentType.xml,
      final t when t.contains('html') => RawContentType.html,
      final t when t.contains('javascript') => RawContentType.javascript,
      _ => RawContentType.text,
    };
    final text = switch (example) {
      null => '',
      String() => example,
      _ => contentType == RawContentType.json ? _jsonIndent.convert(example) : '',
    };
    final essence = mediaType.split(';').first.trim().toLowerCase();
    final explicit = essence == contentType.mimeType || essence.contains('*') ? null : mediaType;
    return (RequestBody(type: BodyType.raw, rawContentType: contentType, rawText: text), explicit);
  }

  List<KeyValueItem> _formFieldsOf(Map<String, dynamic> rawSchema) {
    final schema = _flatten(rawSchema);
    return [
      for (final e in _map(schema['properties']).entries)
        if (_flatten(_map(e.value))['format'] != 'binary')
          KeyValueItem(key: e.key, value: _text(_example(_map(e.value)) ?? '')),
    ];
  }

  dynamic _example(Map<String, dynamic> schema) {
    final example = _exampleOf(schema, _Expansion());
    return identical(example, _cut) ? null : example;
  }

  /// Builds a placeholder value from a schema, or [_cut] where expansion had
  /// to stop. A `$ref` already in [_Expansion.visiting] is a schema that
  /// contains itself, so it is cut at its second appearance. That includes a
  /// `$ref` wrapped as `allOf: [{$ref}]` (how many generators spell a
  /// nullable or described reference): merging it in would re-expand the
  /// schema forever, so its members are held on the path like a direct ref.
  dynamic _exampleOf(Map<String, dynamic> node, _Expansion ex) {
    final ref = node[r'$ref'];
    if (ref is String) {
      if (!ex.visiting.add(ref)) return _cut;
      final result = _exampleOf(_resolve(node), ex);
      ex.visiting.remove(ref);
      return result;
    }
    final members = [for (final m in _list(node['allOf'])) if (_map(m)[r'$ref'] case final String memberRef) memberRef];
    if (members.any(ex.visiting.contains) || ex.depth >= _Expansion.maxDepth || ex.nodes >= _Expansion.maxNodes) {
      return _cut;
    }
    ex.nodes++;
    ex.depth++;
    ex.visiting.addAll(members);
    final example = _valueOf(_flatten(node), ex);
    ex.visiting.removeAll(members);
    ex.depth--;
    return example;
  }

  dynamic _valueOf(Map<String, dynamic> schema, _Expansion ex) {
    if (schema.containsKey('example')) return schema['example'];
    if (schema.containsKey('default')) return schema['default'];
    final examples = _first(schema['examples']) ?? _first(schema['enum']);
    if (examples != null) return examples;
    for (final key in const ['oneOf', 'anyOf']) {
      final options = _list(schema[key]);
      if (options.isNotEmpty) return _exampleOf(_map(options.first), ex);
    }
    final properties = _map(schema['properties']);
    final type = _typeOf(schema);
    if (type == 'object' || properties.isNotEmpty) {
      final object = <String, dynamic>{};
      for (final e in properties.entries) {
        final value = _exampleOf(_map(e.value), ex);
        if (!identical(value, _cut)) object[e.key] = value;
      }
      return object;
    }
    return switch (type) {
      'array' => _arrayOf(schema['items'], ex),
      'integer' => 0,
      'number' => 0.0,
      'boolean' => true,
      'string' => _stringExample(schema['format']),
      _ => null,
    };
  }

  List<dynamic> _arrayOf(dynamic items, _Expansion ex) {
    final item = items is Map ? _exampleOf(_map(items), ex) : _cut;
    return identical(item, _cut) ? [] : [item];
  }

  static String? _typeOf(Map<String, dynamic> schema) {
    final type = schema['type'];
    if (type is List) return type.map((t) => '$t').where((t) => t != 'null').firstOrNull;
    return type is String ? type : null;
  }

  static String _stringExample(dynamic format) => switch (format) {
        'date' => '2024-01-01',
        'date-time' => '2024-01-01T00:00:00Z',
        'email' => 'user@example.com',
        'uuid' => '00000000-0000-0000-0000-000000000000',
        'uri' || 'url' => 'https://example.com',
        'binary' || 'byte' => '',
        _ => 'string',
      };

  /// Resolves a schema's `$ref` and merges `allOf` members into one flat
  /// schema so property lookups see every inherited field. [chain] holds the
  /// `$ref`s being merged, so an `allOf` loop ends instead of recursing
  /// forever.
  Map<String, dynamic> _flatten(Map<String, dynamic> node, [Set<String> chain = const {}]) {
    final ref = node[r'$ref'];
    if (ref is String && chain.contains(ref)) return const {};
    final schema = _resolve(node);
    final allOf = _list(schema['allOf']);
    if (allOf.isEmpty) return schema;
    final inner = ref is String ? {...chain, ref} : chain;
    final merged = <String, dynamic>{...schema}..remove('allOf');
    final properties = <String, dynamic>{};
    for (final member in allOf) {
      final flat = _flatten(_map(member), inner);
      properties.addAll(_map(flat['properties']));
      for (final e in flat.entries) {
        if (e.key != 'properties') merged.putIfAbsent(e.key, () => e.value);
      }
    }
    merged['properties'] = {...properties, ..._map(schema['properties'])};
    return merged;
  }

  RequestAuth _authOf(Map<String, dynamic> operation) {
    final requirements = operation.containsKey('security') ? operation['security'] : _root['security'];
    if (requirements is! List) return const RequestAuth(type: AuthType.inherit);
    if (requirements.isEmpty) return RequestAuth.none;
    final schemes = _isSwagger2 ? _map(_root['securityDefinitions']) : _map(_map(_root['components'])['securitySchemes']);
    for (final requirement in requirements.whereType<Map>()) {
      for (final entry in requirement.entries) {
        final auth = _authFromScheme(_resolve(_map(schemes['${entry.key}'])), _list(entry.value));
        if (auth != null) return auth;
      }
    }
    return const RequestAuth(type: AuthType.inherit);
  }

  /// [requiredScopes] are the scopes this operation's security requirement
  /// asks of the scheme.
  static RequestAuth? _authFromScheme(Map<String, dynamic> scheme, List<dynamic> requiredScopes) {
    const bearer = RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}');
    const basic = RequestAuth(type: AuthType.basic, basicUsername: '{{username}}', basicPassword: '{{password}}');
    switch (scheme['type']) {
      case 'http':
        return switch ('${scheme['scheme']}'.toLowerCase()) {
          'bearer' => bearer,
          'basic' => basic,
          'digest' => basic.copyWith(type: AuthType.digest),
          _ => null,
        };
      case 'basic':
        return basic;
      case 'apiKey':
        final location = scheme['in'];
        if (location != 'header' && location != 'query') return null;
        return RequestAuth(
          type: AuthType.apiKey,
          apiKeyName: _str(scheme['name']) ?? '',
          apiKeyValue: '{{apiKey}}',
          apiKeyLocation: location == 'query' ? ApiKeyLocation.query : ApiKeyLocation.header,
        );
      case 'oauth2':
        return _oauth2Of(scheme, requiredScopes) ?? bearer;
      case 'openIdConnect':
        return bearer;
      default:
        return null;
    }
  }

  /// Keeps the token/authorization URLs and scopes for the grants the app can
  /// run. Null for the implicit flow (no token endpoint to call) and anything
  /// unrecognised, which fall back to a manually pasted bearer token.
  static RequestAuth? _oauth2Of(Map<String, dynamic> scheme, List<dynamic> requiredScopes) {
    final flows = scheme.containsKey('flows') ? _map(scheme['flows']) : {'${scheme['flow']}': scheme};
    for (final entry in flows.entries) {
      final grant = switch (entry.key) {
        'clientCredentials' || 'application' => OAuth2GrantType.clientCredentials,
        'password' => OAuth2GrantType.password,
        'authorizationCode' || 'accessCode' => OAuth2GrantType.authorizationCodePkce,
        _ => null,
      };
      if (grant == null) continue;
      final flow = _map(entry.value);
      final Iterable<dynamic> scopes = requiredScopes.isNotEmpty ? requiredScopes : _map(flow['scopes']).keys;
      return RequestAuth(
        type: AuthType.oauth2,
        oauth2GrantType: grant,
        oauth2AccessTokenUrl: _str(flow['tokenUrl']) ?? '',
        oauth2AuthorizationUrl: _str(flow['authorizationUrl']) ?? '',
        oauth2ClientId: '{{clientId}}',
        oauth2ClientSecret: grant == OAuth2GrantType.authorizationCodePkce ? '' : '{{clientSecret}}',
        oauth2Scope: scopes.join(' '),
        oauth2Username: grant == OAuth2GrantType.password ? '{{username}}' : '',
        oauth2Password: grant == OAuth2GrantType.password ? '{{password}}' : '',
      );
    }
    return null;
  }

  /// Follows a local `#/...` JSON pointer one hop. External refs and
  /// dangling pointers resolve to an empty map so the caller just sees
  /// "nothing here".
  Map<String, dynamic> _resolve(Map<String, dynamic> node) {
    final ref = node[r'$ref'];
    if (ref is! String) return node;
    if (!ref.startsWith('#/')) return const {};
    dynamic current = _root;
    for (final segment in ref.substring(2).split('/')) {
      if (current is! Map) return const {};
      current = current[_unescapePointer(segment)];
    }
    return _map(current);
  }

  /// RFC 6901 §6: a pointer inside a `$ref` is percent-encoded
  /// (`Pet%20Store`, `Result%C2%ABUser%C2%BB`), then `~1`/`~0` stand for
  /// `/`/`~`. A malformed escape is taken literally.
  static String _unescapePointer(String segment) {
    String decoded;
    try {
      decoded = Uri.decodeComponent(segment);
    } catch (_) {
      decoded = segment;
    }
    return decoded.replaceAll('~1', '/').replaceAll('~0', '~');
  }

  dynamic _firstExampleValue(dynamic examples) {
    final first = _first(_map(examples).values);
    return first == null ? null : _resolve(_map(first))['value'];
  }

  static Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};
  static List<dynamic> _list(dynamic v) => v is List ? v : const [];
  static dynamic _first(dynamic v) => v is Iterable && v.isNotEmpty ? v.first : null;
  static String? _str(dynamic v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
  static String _text(dynamic v) => v is String ? v : (v is num || v is bool ? '$v' : jsonEncode(v));
  static String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  /// The variable resolver only matches `\w+`, so `{user-id}` has to become
  /// `{{user_id}}` to ever be substituted.
  static String _placeholder(String name) => '{{${name.replaceAll(_nonWord, '_')}}}';
}

/// State for expanding one schema into an example. [visiting] holds the
/// `$ref`s being expanded right now (cycle guard); [depth] and [nodes] cap
/// what that can't: cycles hidden behind `allOf` chains, and shared schemas
/// that fan out exponentially.
final class _Expansion {
  static const maxDepth = 10;
  static const maxNodes = 1000;

  final visiting = <String>{};
  int depth = 0;
  int nodes = 0;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
