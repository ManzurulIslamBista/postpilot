import 'dart:convert';
import 'package:yaml/yaml.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/domain/entities/request_auth.dart';
import '../../../request_builder/domain/entities/request_body.dart';
import '../entities/imported_collection.dart';
import 'imported_body_mapper.dart';

/// A sub-environment of an Insomnia workspace.
final class ParsedInsomniaEnvironment {
  final String name;
  final List<KeyValueItem> variables;
  const ParsedInsomniaEnvironment(this.name, this.variables);
}

final class ParsedInsomniaWorkspace {
  /// The request tree, with the workspace's base environment as collection variables.
  final ImportedCollection collection;
  final List<ParsedInsomniaEnvironment> environments;
  const ParsedInsomniaWorkspace(this.collection, this.environments);
}

final class ParsedInsomniaExport {
  final List<ParsedInsomniaWorkspace> workspaces;
  const ParsedInsomniaExport(this.workspaces);
}

/// Parses an Insomnia export: the v3/v4 JSON (`_type: export`, a flat
/// `resources` list linked by `parentId`) and, best-effort, the v5 YAML
/// (`type: collection.insomnia.rest/5.0`, a nested `collection` tree). One
/// collection comes out per workspace, folders nested as in Insomnia.
///
/// Insomnia's `{{ _.name }}` references become `{{name}}`, `uuid`/`now` tags
/// map to the matching built-in dynamic variables, and a folder's headers and
/// auth flow down to the requests below it that set none of their own. Anything
/// the app can't represent (gRPC/WebSocket requests, file bodies, hawk/ntlm/
/// oauth1 auth, response-chaining tags) is left out or kept as literal text
/// rather than rejected.
abstract final class InsomniaParser {
  static final _envReference = RegExp(r'\{\{\s*(?:_\.)?([\w.$-]+)\s*\}\}');
  static final _uuidTag = RegExp(r'''\{%\s*uuid\s*(?:['"]v\d['"])?\s*%\}''');
  static final _nowTag = RegExp(r'''\{%\s*now\s*['"](iso-8601|unix)['"][^%]*%\}''');
  static const _maxDepth = 64;

  static ParsedInsomniaExport parse(String text) {
    final root = _decode(text);
    final type = root['type'];
    if (root['_type'] == 'export') return _parseResources(root);
    if (type is String && type.startsWith('collection.insomnia.rest/')) return _parseCollectionDocument(root);
    if (type is String && type.startsWith('spec.insomnia.rest/')) {
      throw const ImportException('this is an Insomnia design document; export a collection instead.');
    }
    throw const ImportException('no Insomnia export marker found ("_type": "export" or "type: collection.insomnia.rest/5.0").');
  }

  static Map<String, dynamic> _decode(String text) {
    final trimmed = text.replaceFirst('﻿', '').trim();
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

  // ---- v3/v4: flat resources ----------------------------------------------

  static ParsedInsomniaExport _parseResources(Map<String, dynamic> root) {
    final resources = [
      for (final r in _list(root['resources']))
        if (r is Map) r.cast<String, dynamic>(),
    ];
    final known = {for (final r in resources) if (r['_id'] is String) r['_id'] as String};
    final byParent = <String, List<Map<String, dynamic>>>{};
    for (final r in resources) {
      final parent = r['parentId'];
      if (parent is String) byParent.putIfAbsent(parent, () => []).add(r);
    }

    // Items of a partial export (one folder or request) whose workspace isn't in the file.
    final orphans = [
      for (final r in resources)
        if (_isItem(r) && !known.contains(r['parentId'])) r,
    ];
    final workspaceResources = resources.where((r) => r['_type'] == 'workspace').toList();
    if (workspaceResources.isEmpty && orphans.isEmpty) {
      throw const ImportException('the export holds no workspace, folder or request.');
    }

    final workspaces = <ParsedInsomniaWorkspace>[];
    for (var i = 0; i < workspaceResources.length; i++) {
      final workspace = workspaceResources[i];
      final children = byParent[workspace['_id']] ?? const [];
      final items = _v4Items([...children, if (i == 0) ...orphans], byParent, const [], null, 0);
      final base = children.where((c) => c['_type'] == 'environment').firstOrNull;
      final subEnvironments = base == null
          ? const <Map<String, dynamic>>[]
          : [for (final e in byParent[base['_id']] ?? const <Map<String, dynamic>>[]) if (e['_type'] == 'environment') e];
      workspaces.add(ParsedInsomniaWorkspace(
        ImportedCollection(
          _str(workspace['name']) ?? 'Imported from Insomnia',
          items,
          variables: base == null ? const [] : _variablesOf(base['data']),
        ),
        [
          for (final e in _sorted(subEnvironments, (e) => _num(e['metaSortKey'])))
            ParsedInsomniaEnvironment(_str(e['name']) ?? 'Environment', _variablesOf(e['data'])),
        ],
      ));
    }
    if (workspaceResources.isEmpty) {
      workspaces.add(ParsedInsomniaWorkspace(
        ImportedCollection('Imported from Insomnia', _v4Items(orphans, byParent, const [], null, 0)),
        const [],
      ));
    }
    return ParsedInsomniaExport(workspaces);
  }

  static bool _isItem(Map<String, dynamic> resource) =>
      resource['_type'] == 'request' || resource['_type'] == 'request_group';

  static List<ImportedItem> _v4Items(
    List<Map<String, dynamic>> children,
    Map<String, List<Map<String, dynamic>>> byParent,
    List<KeyValueItem> inheritedHeaders,
    RequestAuth? inheritedAuth,
    int depth,
  ) {
    if (depth > _maxDepth) return const [];
    final items = <ImportedItem>[];
    for (final child in _sorted(children, (c) => _num(c['metaSortKey']))) {
      switch (child['_type']) {
        case 'request_group':
          final headers = _mergeHeaders(inheritedHeaders, _keyValues(child['headers']));
          final auth = _explicitAuth(child['authentication']) ?? inheritedAuth;
          items.add(ImportedFolder(
            _str(child['name']) ?? 'Folder',
            _v4Items(byParent[child['_id']] ?? const [], byParent, headers, auth, depth + 1),
          ));
        case 'request':
          items.add(_request(child, inheritedHeaders, inheritedAuth));
      }
    }
    return items;
  }

  // ---- v5: nested collection document -------------------------------------

  static ParsedInsomniaExport _parseCollectionDocument(Map<String, dynamic> root) {
    final environments = root['environments'];
    final environmentMap = environments is Map ? environments.cast<String, dynamic>() : const <String, dynamic>{};
    return ParsedInsomniaExport([
      ParsedInsomniaWorkspace(
        ImportedCollection(
          _str(root['name']) ?? 'Imported from Insomnia',
          _v5Items(_list(root['collection']), const [], null, 0),
          variables: _variablesOf(environmentMap['data']),
        ),
        [
          for (final e in _list(environmentMap['subEnvironments']))
            if (e is Map) ParsedInsomniaEnvironment(_str(e['name']) ?? 'Environment', _variablesOf(e['data'])),
        ],
      ),
    ]);
  }

  static List<ImportedItem> _v5Items(List<dynamic> entries, List<KeyValueItem> inheritedHeaders, RequestAuth? inheritedAuth, int depth) {
    if (depth > _maxDepth) return const [];
    final maps = [for (final e in entries) if (e is Map) e.cast<String, dynamic>()];
    final items = <ImportedItem>[];
    for (final entry in _sorted(maps, (e) => _num(_map(e['meta'])['sortKey']))) {
      if (entry['children'] is List) {
        final headers = _mergeHeaders(inheritedHeaders, _keyValues(entry['headers']));
        final auth = _explicitAuth(entry['authentication']) ?? inheritedAuth;
        items.add(ImportedFolder(_str(entry['name']) ?? 'Folder', _v5Items(_list(entry['children']), headers, auth, depth + 1)));
      } else if (entry['url'] is String || entry['method'] is String) {
        items.add(_request(entry, inheritedHeaders, inheritedAuth));
      }
    }
    return items;
  }

  // ---- requests -----------------------------------------------------------

  static ImportedRequest _request(Map<String, dynamic> r, List<KeyValueItem> inheritedHeaders, RequestAuth? inheritedAuth) {
    final headers = _mergeHeaders(inheritedHeaders, _keyValues(r['headers']));
    final (body, contentType) = _bodyOf(r['body']);
    if (contentType != null && !ImportedBodyMapper.hasContentType(headers)) {
      headers.add(KeyValueItem(key: ImportedBodyMapper.contentTypeHeader, value: contentType));
    }
    final url = _template('${r['url'] ?? ''}');
    return ImportedRequest(
      _str(r['name']) ?? (url.isEmpty ? 'Untitled' : url),
      method: HttpMethod.fromString(_str(r['method'])),
      url: url,
      headers: headers,
      queryParams: _keyValues(r['parameters']),
      body: body,
      auth: _explicitAuth(r['authentication']) ?? inheritedAuth ?? const RequestAuth(),
    );
  }

  /// A folder's headers apply to every request below it; the request's own
  /// header of the same name wins.
  static List<KeyValueItem> _mergeHeaders(List<KeyValueItem> inherited, List<KeyValueItem> own) => [
        for (final h in inherited)
          if (!own.any((o) => o.key.toLowerCase() == h.key.toLowerCase())) h,
        ...own,
      ];

  static List<KeyValueItem> _keyValues(dynamic list, {bool skipFiles = false}) => [
        for (final e in _list(list))
          if (e is Map && _str(e['name']) != null && !(skipFiles && e['type'] == 'file'))
            KeyValueItem(key: _template(_str(e['name'])!), value: _template('${e['value'] ?? ''}'), enabled: e['disabled'] != true),
      ];

  static (RequestBody, String?) _bodyOf(dynamic raw) {
    if (raw is! Map) return (RequestBody.empty, null);
    final mime = _str(raw['mimeType']) ?? '';
    final text = raw['text'] is String ? _template(raw['text'] as String) : '';
    if (mime.contains('x-www-form-urlencoded')) {
      return (RequestBody(type: BodyType.urlEncoded, urlEncodedFields: _keyValues(raw['params'], skipFiles: true)), null);
    }
    if (mime.contains('multipart')) {
      return (RequestBody(type: BodyType.formData, formFields: _keyValues(raw['params'], skipFiles: true)), null);
    }
    if (mime == 'application/graphql') return (_graphqlBody(text), null);
    if (text.isEmpty || mime == 'application/octet-stream') return (RequestBody.empty, null);
    if (mime.isEmpty) {
      return (RequestBody(type: BodyType.raw, rawContentType: ImportedBodyMapper.sniffRawType(text), rawText: text), null);
    }
    return ImportedBodyMapper.raw(mime, text);
  }

  /// Insomnia stores a GraphQL body as one JSON string `{"query": ..., "variables": ...}`.
  static RequestBody _graphqlBody(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final variables = decoded['variables'];
        return RequestBody(
          type: BodyType.graphql,
          graphqlQuery: '${decoded['query'] ?? ''}',
          graphqlVariables: variables is String ? variables : jsonEncode(variables ?? const {}),
        );
      }
    } on FormatException {
      // Not the JSON envelope: the text itself is the query.
    }
    return RequestBody(type: BodyType.graphql, graphqlQuery: text);
  }

  // ---- auth ---------------------------------------------------------------

  /// Null when the request or folder sets no auth of its own (an absent or
  /// empty `authentication`), which means "inherit".
  static RequestAuth? _explicitAuth(dynamic raw) {
    if (raw is! Map) return null;
    final type = _str(raw['type']);
    if (type == null) return null;
    if (raw['disabled'] == true) return RequestAuth.none;
    return _authOf(type, raw.cast<String, dynamic>());
  }

  static RequestAuth _authOf(String type, Map<String, dynamic> a) {
    String s(String key) => _template('${a[key] ?? ''}');
    switch (type) {
      case 'bearer':
        return RequestAuth(type: AuthType.bearer, bearerToken: s('token'));
      case 'basic':
        return RequestAuth(type: AuthType.basic, basicUsername: s('username'), basicPassword: s('password'));
      case 'digest':
        return RequestAuth(type: AuthType.digest, basicUsername: s('username'), basicPassword: s('password'));
      case 'apikey':
        return RequestAuth(
          type: AuthType.apiKey,
          apiKeyName: s('key'),
          apiKeyValue: s('value'),
          apiKeyLocation: a['addTo'] == 'queryParams' ? ApiKeyLocation.query : ApiKeyLocation.header,
        );
      case 'iam':
      case 'aws-iam':
        return RequestAuth(
          type: AuthType.awsSignatureV4,
          awsAccessKey: s('accessKeyId'),
          awsSecretKey: s('secretAccessKey'),
          awsSessionToken: s('sessionToken'),
          awsRegion: _str(a['region']) ?? 'us-east-1',
          awsService: _str(a['service']) ?? 'execute-api',
        );
      case 'oauth2':
        return _oauth2Of(a);
      default:
        return RequestAuth.none;
    }
  }

  /// The implicit and refresh-token grants have no token endpoint to call, so
  /// they (like an unknown grant) fall back to a manually pasted bearer token.
  static RequestAuth _oauth2Of(Map<String, dynamic> a) {
    String s(String key) => _template('${a[key] ?? ''}');
    final grant = switch ('${a['grantType']}') {
      'client_credentials' => OAuth2GrantType.clientCredentials,
      'password' => OAuth2GrantType.password,
      'authorization_code' => OAuth2GrantType.authorizationCodePkce,
      _ => null,
    };
    if (grant == null) return const RequestAuth(type: AuthType.bearer, bearerToken: '{{token}}');
    return RequestAuth(
      type: AuthType.oauth2,
      oauth2GrantType: grant,
      oauth2AccessTokenUrl: s('accessTokenUrl'),
      oauth2AuthorizationUrl: s('authorizationUrl'),
      oauth2RedirectUri: s('redirectUrl'),
      oauth2ClientId: s('clientId'),
      oauth2ClientSecret: s('clientSecret'),
      oauth2Scope: s('scope'),
      oauth2Username: s('username'),
      oauth2Password: s('password'),
      oauth2Audience: s('audience'),
      oauth2ClientAuthentication: a['credentialsInBody'] == true ? OAuth2ClientAuthentication.body : OAuth2ClientAuthentication.basicHeader,
    );
  }

  // ---- environments -------------------------------------------------------

  /// Nested objects flatten to dotted keys (`{"db": {"host": "x"}}` -> `db.host`),
  /// which `{{ _.db.host }}` maps to as `{{db.host}}`.
  static List<KeyValueItem> _variablesOf(dynamic data) {
    final variables = <KeyValueItem>[];
    void walk(String key, dynamic value, int depth) {
      if (value is Map && depth < 6) {
        for (final e in value.entries) {
          walk(key.isEmpty ? '${e.key}' : '$key.${e.key}', e.value, depth + 1);
        }
      } else if (key.isNotEmpty) {
        final text = switch (value) {
          null => '',
          String() => _template(value),
          num() || bool() => '$value',
          _ => jsonEncode(value),
        };
        variables.add(KeyValueItem(key: key, value: text));
      }
    }

    walk('', data, 0);
    return variables;
  }

  // ---- helpers ------------------------------------------------------------

  static String _template(String text) => text
      .replaceAllMapped(_uuidTag, (_) => r'{{$guid}}')
      .replaceAllMapped(_nowTag, (m) => m[1] == 'unix' ? r'{{$timestamp}}' : r'{{$isoTimestamp}}')
      .replaceAllMapped(_envReference, (m) => '{{${m[1]}}}');

  /// Ascending by [key] with the original order kept for ties (`List.sort` isn't stable).
  static List<T> _sorted<T>(List<T> items, num Function(T) key) {
    final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
    indexed.sort((a, b) {
      final byKey = key(a.$2).compareTo(key(b.$2));
      return byKey != 0 ? byKey : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  static num _num(dynamic value) => value is num ? value : 0;
  static Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};
  static List<dynamic> _list(dynamic v) => v is List ? v : const [];
  static String? _str(dynamic v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
}
